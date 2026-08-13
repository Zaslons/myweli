# G1 — the backend moves to Google Cloud

> Module: **infrastructure**. Supersedes `render.yaml` as the deployment target.
> Prior art: [`DEPLOYMENT.md`](../DEPLOYMENT.md) (the Render-shaped runbook this
> rewrites), [`backend-q1-funnel-smoke.md`](backend-q1-funnel-smoke.md) (the
> gate that proves the funnel still works after the move).

## 1. Goal & scope

Move the dart_frog backend from Render to Google Cloud: **Cloud Run** +
**Cloud SQL** + **Cloud Scheduler** + **Secret Manager** + **Artifact
Registry**, deployed from GitHub Actions.

**Why now rather than after the beta.** The Render free Postgres appears to have
expired — every DB-backed route answers 500 — so the database must be
re-provisioned and re-seeded regardless. That makes this the one moment where
the migration carries **no data-migration cost**, and doing it now means paying
the setup once instead of twice.

**Why GCP is the destination** (settled with the owner): Firebase/FCM is already
Google and consolidating billing + IAM has lasting operational value; Cloud SQL
is a more serious system of record (PITR, backups, replicas, HA) for a business
where losing a day of appointments is a business event; Cloud Scheduler and
Cloud Tasks are the natural homes for the reminder cron now and retryable
outbound messaging when SMS/WhatsApp arrive; and the compliance posture is what
ARTCI (OQ-7) and any future payment partner will actually accept.

### 1.1 In scope

- Cloud Run service for the backend, from the existing `backend/Dockerfile`.
- Cloud SQL for PostgreSQL 16, private, reached through the **Cloud SQL Auth
  Proxy sidecar**.
- Secret Manager for every secret; plain env vars for non-secret config.
- Cloud Scheduler for the two cron routes that exist but have never been
  scheduled from the repo.
- GitHub Actions deploy via **Workload Identity Federation** — no long-lived
  service-account JSON key in the repo or in GitHub secrets.
- Two **correctness fixes that the move forces** (§3) — both shipped and green
  *before* cutover.
- Rewriting `DEPLOYMENT.md` and retiring `render.yaml`.

### 1.2 Explicitly NOT moving

- **Cloudflare R2** stays. Zero egress is a real advantage when serving salon
  photos to phones on expensive West-African bandwidth; GCS would bill every
  byte. This is a deliberate multi-cloud choice, not an oversight.
- **Vercel** stays for the Next.js site. It is the best host for Next, and Cloud
  Run would be a downgrade.
- Firebase/FCM is unchanged (it was already Google).
- SMS/WhatsApp remain deferred until company registration — no Twilio or Meta
  work here. The deferral is now **expressible in config** rather than an
  unbootable gap: see §3.3.

## 2. What Render actually provided, and its GCP equivalent

Measured from `render.yaml` (34 declared keys) and
`backend/lib/src/dependencies.dart` (35 read, plus `PORT` injected by the
platform):

| Render | GCP | Note |
|---|---|---|
| `type: web`, `plan: starter` | Cloud Run service | Same container; Cloud Run injects `PORT`, which the entrypoint already reads and binds dual-stack |
| `databases: myweli-db` | Cloud SQL Postgres 16 | reached via the Auth Proxy sidecar (§4.1) |
| `fromDatabase: connectionString` | `DATABASE_URL` built by us | the one value that cannot be copied — it is Render-shaped |
| `generateValue: true` ×3 | Secret Manager secrets we mint | `JWT_SECRET`, `MESSAGING_WEBHOOK_SECRET`, `CRON_SECRET` |
| `sync: false` ×26 | Secret Manager / env | values live in the owner's head or the Render dashboard |
| dashboard cron jobs (**invisible to the repo**) | Cloud Scheduler | see §5 — and note the honesty gap recorded there: the jobs exist in the project but are still not declared in this repo |
| auto-deploy from GitHub | GitHub Actions + WIF | explicit, reviewable, no platform magic |

**The three generated secrets can be re-minted rather than copied.** There are
no real users yet — the beta has not started — so rotating `JWT_SECRET` costs
nothing. Copying it out of a dashboard into a new cloud is the kind of step that
goes wrong quietly; minting fresh is safer and equally correct *at this moment
only*. After launch this stops being true.

## 3. Two correctness fixes the move forces

Both are backend changes, both ship **before** cutover, both watched red first.

### 3.1 `DATABASE_URL` must fail fast in production

`dependencies.dart:111-118`:

```dart
final String? _databaseUrl = () {
  final url = Platform.environment['DATABASE_URL'];
  return (url == null || url.isEmpty) ? null : url;
}();
final Pool<void>? _pool = _databaseUrl == null ? null : createPool(_databaseUrl!);
```

`JWT_SECRET` throws in prod (`:104-106`). `DATABASE_URL` does not — and every
repository silently falls back to its `InMemory` variant. **A Cloud Run
revision deployed without it would serve a green, healthy-looking API in which
every booking is lost the moment the instance recycles**, with `/health`
reporting `ok` throughout.

That risk is theoretical on Render, where the value is wired by a service
reference that cannot be forgotten. On Cloud Run it is a one-line omission. So:
throw in prod, exactly as `JWT_SECRET` does. Gate: a test that boots the
composition root with `ENV=prod` and no `DATABASE_URL` and expects a
`StateError`.

### 3.2 Migrations must not race across instances

`backend/main.dart:10-13` awaits `initializeDatabase()` — migrations plus seed —
before `serve()`. On Render that ran once, on one always-on instance. **Cloud
Run scales horizontally and starts cold instances concurrently**, so two
instances can enter the migration path at the same time.

Fix: wrap the migration run in a Postgres **advisory lock**
(`pg_advisory_lock(<constant>)`), so a second instance blocks until the first
finishes and then observes the schema as current. Gate: a test that runs two
`initializeDatabase()` calls concurrently against one database and asserts a
single application of each migration.

This is the single largest correctness risk in the move, and it is invisible
until it corrupts something.

### 3.3 Production must be able to run with messaging deliberately off

> **Correction (measured on the deployed service).** This section originally
> claimed the backend "could not have booted on Cloud Run at all". **That was
> wrong.** `assertProductionBootConfig` (`boot_config.dart:75-82`) checks only
> `DATABASE_URL` and `JWT_SECRET`; `messagingProvider` is a lazy top-level
> `final` (`dependencies.dart:536`) that `initializeDatabase()` never touches.
> The old code would have **booted, gone green, passed the health check and
> taken traffic** — then 500'd on the first booking transition or reminder tick.
> That is *worse* than a boot failure, not better: the failure moves from deploy
> time to user time. The fix below is right; only the severity was misstated.
>
> This is now proven rather than argued — see §3.4.

Found while writing the secret checklist (§7): production refuses to start
without SMS credentials. `dependencies.dart:604` refuses to start in
production unless Termii or Twilio credentials are present, and `:585` refuses
`MESSAGING_PROVIDER=log` outright — correctly, because the log provider answers
`ok: true` and the outbox would record a phantom `sent` for every message nobody
received.

Both guards are right. Together they assume something that is no longer true:
that production always has an SMS channel. The owner's decision defers SMS and
WhatsApp until **company registration, which happens after launch** — Termii's
branded sender needs ARTCI and a WhatsApp business number needs Meta
verification. So at launch there is no channel to configure, and the only ways
to deploy were to **lie** (`log`) or to **buy** credentials we do not want.

Fix: `MESSAGING_PROVIDER=disabled`, a fourth selector value that production
accepts. It is deliberately *not* a weakening of either guard:

- **Explicit only.** It is never auto-detected, so "nothing configured" still
  hits the `:604` fail-fast. The accidental case stays fatal; only the typed,
  deliberate one passes.
- **Honest.** It reports `ok: false`, so `messaging_service.dart:61` writes
  `DeliveryStatus.failed` to the outbox — a queryable record of what was never
  delivered, which is what we will want the day the channel is switched on and
  someone asks what was missed. This is the entire difference from `log`, and it
  is why `log` stays refused.

**What runs on push and email alone.** `AUTH_METHODS=google,apple,email` already
excludes phone, so sign-in is unaffected — the OTP path is unreachable, not
broken. Booking confirmations and reminders lose their SMS leg and keep push +
email. The reminder cron (§5) still runs and still writes outbox rows; they will
read `failed` for the SMS channel, which is accurate.

Gate: `backend/test/disabled_messaging_provider_test.dart` — four tests, pinning
`ok: false`, the `messaging_disabled` reason code, every channel off (the
WhatsApp→SMS retry at `messaging_service.dart:46` means a half-off provider
would silently deliver half the traffic), and the it-must-differ-from-`log`
property, stated as a test because the two are one keyword apart in the selector
and aliasing them would be an easy invisible "simplification".

### 3.4 The lazy-guard class — measured in production, still open

The first Cloud Run revision was deployed deliberately with **only** the four
secrets we mint (`DATABASE_URL`, `JWT_SECRET`, `CRON_SECRET`,
`MESSAGING_WEBHOOK_SECRET`) and none of the owner-supplied values. Result:

- `/health` → **200**, `/providers` → **200 with real seeded rows** from Cloud
  SQL through the sidecar. Migrations ran. The revision was marked ready and
  took 100% of traffic.
- `POST /internal/cron/reminders` with the correct secret → **500**:
  `Bad state: Push must be configured in production: set FCM_PROJECT_ID,
  FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY (service account).`

So a production deployment missing R2, FCM, Google, Apple and Resend entirely
**looks completely healthy** to Cloud Run and to any uptime check pointed at
`/health`. Every one of those guards is a lazy `final` injected through
`routes/_middleware.dart`, and it first runs on the request that touches it.

`DATABASE_URL` and `JWT_SECRET` were closed by §3.1. The rest of the class was
not. Two consequences worth acting on separately from the cutover:

1. **`R2_PUBLIC_BASE_URL` has a second reader that bypasses its own fail-fast.**
   `_galleryAllowedOrigins` (`dependencies.dart:346-349`) reads it directly, so
   when it is unset the gallery / before-after / review-photo origin allowlist
   is simply **off** — and those routes return **200** while `/uploads/sign`
   is 500ing. Silent, and it is a security control.
2. **The reminder cron is loud but wrongly ordered.** In
   `routes/appointments/index.dart:165` the appointment is committed *before*
   the push notifier is read, and `unawaited(context.read<…>())` evaluates the
   read synchronously — so an unconfigured FCM returns **500 for a booking that
   actually succeeded**. Same shape in `cancel.dart:20-26`.

Recommended follow-up (not this PR): extend `assertProductionBootConfig` to
force every prod-required dependency at boot, so the whole class fails at deploy
time instead of at user time.

## 4. Architecture decisions

### 4.1 Cloud SQL via the Auth Proxy sidecar — chosen for zero code change

Three options were considered:

| Option | Verdict |
|---|---|
| Cloud Run's built-in Cloud SQL mount (unix socket `/cloudsql/…`) | **Rejected** — the Dart `postgres` pool is built from a `host:port` URL; a unix socket does not fit `createPool(DATABASE_URL)` without a code change |
| Private IP + Direct VPC egress | Viable, lowest latency, but needs a VPC, a subnet and private services access — more moving parts to get wrong on day one |
| **Auth Proxy sidecar** | **Chosen.** `DATABASE_URL` becomes `postgres://user:pass@127.0.0.1:5432/myweli`, the proxy encrypts the hop, and `createPool` already treats a local host as "no SSL needed" (`render.yaml:11` records that behaviour). **Zero application change.** |

Revisit private IP later if the proxy's per-instance overhead shows up in
latency; it is an infrastructure change with no code impact.

### 4.2 Region: `europe-west9` (Paris)

Render was Frankfurt. Paris is marginally closer to Abidjan and keeps the same
EU posture, so the ARTCI answer (OQ-7) is no worse than today. Cloud Run and
Cloud SQL are both available there. **This is not a data-residency solution** —
neither cloud has West Africa — and the open question stays open.

### 4.3 Infrastructure as idempotent `gcloud` scripts, not Terraform

`infra/gcp/` holds numbered, re-runnable shell scripts plus a Cloud Run
`service.yaml`. Rationale: Terraform's correctness advantage comes with a state
backend to provision and guard, and this is one service, one database and two
scheduler jobs operated by one person. The scripts give the same property that
made `render.yaml` good — *the infrastructure is in the repo and reviewable* —
without the state. If the estate grows past a handful of resources, Terraform
becomes worth it; that is a later decision, not a now one.

Every script is idempotent (`describe || create`) so a partial run can simply be
re-run.

### 4.4 Deploy via Workload Identity Federation

No service-account JSON key anywhere. GitHub Actions authenticates to GCP with
its OIDC token, federated to a service account scoped to exactly: push to
Artifact Registry, deploy Cloud Run, read the named secrets. A leaked repo then
leaks no credential.

## 5. Cron, finally visible

`/internal/cron/reminders` and `/internal/cron/subscriptions` exist
(`routes/internal/cron/`), take `X-Cron-Secret`, and **return 404 when
`CRON_SECRET` is unset** — so they fail *silently*, which is how reminders came
to be off without anyone noticing. Nothing in the repo ever scheduled them; they
were Render dashboard jobs, invisible to review.

Two Cloud Scheduler jobs:

> **They are not yet declared in this repo.** `infra/gcp/` holds only
> `70-load-balancer.sh`, `80-uptime-checks.sh` and the service manifests, so the
> jobs below were created by hand and exist only in the project. That is a
> weaker version of the exact failure this section is about — Render's cron
> jobs were invisible to review, and these are merely *less* invisible. Committing
> them is owed.


| Job | Schedule | Target |
|---|---|---|
| `myweli-reminders` | every 15 min | `POST /internal/cron/reminders` |
| `myweli-subscriptions` | daily 03:00 UTC | `POST /internal/cron/subscriptions` |

Both send `X-Cron-Secret` from Secret Manager. **A follow-up should make an
unset `CRON_SECRET` fail fast in prod too** — a 404 that means "silently
disabled" is the same class of defect as §3.1, and it is why nobody noticed the
reminder cron was never running.

## 6. Cutover

1. Ship §3.1, §3.2 and §3.3, green, on `main`. (§3.3 is not a boot blocker — see the correction in that section — but without it every booking transition and reminder 500s.)
2. Provision GCP (§7), seed, and run the **Q1 funnel smoke against the Cloud Run
   URL** — 47 assertions over real HTTP are exactly the acceptance test for
   "this environment works", and they already exist.
3. Point `api.myweli.com` at Cloud Run.
4. Watch, then delete the Render services and remove `render.yaml`. — **DONE
   2026-08-13.** §9 Q4 chose "keep the services a week as a rollback"; the week
   ran from the 2026-08-06 cutover and elapsed without a rollback being needed,
   so the file is deleted and the Render account holds nothing.

No traffic-splitting or dual-run: there are no users yet, so a clean cutover is
simpler and safer than a migration dance.

### 6.1 What decommissioning actually looked like

Recorded because the *evidence* is the useful part, not the outcome. From
outside the Render dashboard, three signals agreed that the service was gone:

- GitHub still carries two deployment environments Render created,
  `main - myweli-api` and `main - myweli-db`. The last deployment to the first
  is **2026-08-06T18:49:51Z**, ending `failure` → `inactive`. Nothing has
  deployed since, across every merge to `main` in the week that followed — so
  `autoDeploy: true` had already stopped meaning anything.
- `https://myweli-api.onrender.com/health` answers **404 in 0.8s** — Render's
  edge refusing an unknown service, not an app 404 and not a cold start.
- `api.myweli.com` resolves to the Google load-balancer address, and `/health`
  returns 200 from Cloud Run.

**Those two GitHub environments are the last Render residue in this repo.** They
are harmless but misleading: an environment list showing `main - myweli-api`
reads like a live deployment target. Deleting them is a repo-settings action
(Settings → Environments), owner-only.

## 7. Who does what

| Step | Whose |
|---|---|
| `gcloud auth login`, create project, **link billing** | **owner** — needs a browser and a card |
| Enable APIs, Artifact Registry, Cloud SQL, Cloud Run, Secret Manager, Scheduler, WIF | **mine**, once authenticated |
| Supply **15** owner-only values — auth 3 (`GOOGLE_CLIENT_IDS`, `APPLE_CLIENT_IDS`, `RESEND_API_KEY`), R2 **7**, FCM 3 (of which only `FCM_PRIVATE_KEY` is truly secret), admin 2 (`ADMIN_EMAIL`, `ADMIN_PASSWORD`) | **owner** — I never see or store them; they go straight into Secret Manager |
| The rest: 4 minted by me (§2), 8 Twilio/Termii **not supplied at all** (§3.3), `MESSAGING_PROVIDER=disabled` + `ENV`/`TZ`/`AUTH_METHODS`/`WEB_ORIGINS` as plain Cloud Run config | — |

**Corrections to an earlier version of this table**, all verified against the code:

- **R2 is seven values, not five.** `dependencies.dart:308-321` requires
  `R2_ACCOUNT_ID` (or `R2_ENDPOINT`), `R2_BUCKET`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY`, `R2_PUBLIC_BASE_URL`, `R2_KYC_BUCKET` **and**
  `R2_DEPOSIT_BUCKET` simultaneously — all seven or it throws.
- **`ADMIN_EMAIL` / `ADMIN_PASSWORD` were filed as plain config.** They are not:
  `ADMIN_PASSWORD` seeds the super-admin (`dependencies.dart:767-774`) and only
  the owner can choose it. Without them `/admin/auth/login` has no account.
- **`EMAIL_FROM` is optional**, not required — it falls back to
  `'MyWeli <no-reply@myweli.com>'` (`dependencies.dart:198`), the sender the
  design already specifies.
- **`MESSAGING_PROVIDER` must be SET to `disabled`**, not omitted. An earlier
  version of this table put it in the "not supplied" bucket, contradicting §3.3.
  Unset falls through to auto-detect → null → the prod fail-fast.
- **`PUBLIC_BASE_URL` is dead under this config** — its only reader is
  `buildTwilio()` (`dependencies.dart:557`), unreachable while messaging is off.
| Deploy pipeline, service config, scripts, docs | **mine** |
| DNS for `api.myweli.com` | **owner** |

## 7.1 Cutover findings from the real provisioning run

Recorded because each cost a failed deploy or would have:

1. **The proxy sidecar cannot be probed on its database port.** The Cloud SQL
   Auth Proxy binds `127.0.0.1:5432`, and a Cloud Run TCP startup probe cannot
   reach a loopback listener — measured: the proxy logged *"ready for new
   connections"* while the probe failed 24× and the instance was discarded. Use
   the proxy's own health-check server (`--health-check --http-address=0.0.0.0
   --http-port=9090`, probe `GET /startup`). The database port stays on
   loopback.
2. **`run.googleapis.com/container-dependencies` is required, not optional.**
   `main.dart:12` awaits `initializeDatabase()`, which opens a real connection
   at `migrations.dart:885` to take the advisory lock. No retry, no backoff, and
   the image is `FROM scratch` so not even a shell `wait-for-it` is possible.
3. **`timeoutSeconds` must be strictly less than `periodSeconds`** on every
   probe. Cloud Run rejects the service otherwise.
4. **Mint the Cloud SQL password from an alphanumeric charset.** `createPool`
   splits `uri.userInfo` on `:` and passes both halves through verbatim
   (`db/database.dart:10,15-20`) — Dart does not percent-decode `userInfo`. A
   password containing `@` or `/` throws at parse; a raw `:` is silently
   truncated. Note `openssl rand -base64` emits `/` about half the time. (Ours
   was verified alphanumeric.)
5. **Build for `linux/amd64` explicitly.** Cloud Run is amd64-only and a local
   Apple-Silicon `docker build` defaults to arm64.
6. **`FROM scratch` does ship CA certificates** — the Dart runtime layer carries
   301 of them at `/runtime/etc/ssl/certs/`, so outbound TLS to Resend, R2 and
   FCM works. This was checked because it looked like a bug; it is not one.
7. **The service is deployed private.** It requires an IAM identity token today.
   Making it public (`allUsers` → `roles/run.invoker`) is a deliberate step at
   DNS cutover, not something to leave on while the API is half-configured.

## 7.2 `api.myweli.com` needs a load balancer, not a domain mapping

Cloud Run's own custom-domain feature is the obvious answer and **is not
available in `europe-west9`**:

```
$ gcloud beta run domain-mappings create --domain=api.myweli.com --region=europe-west9
501 UNIMPLEMENTED: Creating domain mappings is not allowed in europe-west9.
```

That is the price of §4.2's region choice, and it was not foreseen there.

**Two dead ends worth recording**, because each looks like it should work:

1. `gcloud beta run domain-mappings list --region=europe-west9` **succeeds** and
   returns an empty list. That reads as "supported, none configured" and is not
   — only `create` reveals the truth. An empty list is not evidence of support.
2. A Cloudflare CNAME proxied to the `*.run.app` URL fails: **Cloud Run answers
   404 to any Host header it does not recognise** (verified, with a nonsense
   Host as control), and Cloudflare forwards the original Host by default.

So: a **global external Application Load Balancer** with a serverless NEG —
`infra/gcp/70-load-balancer.sh`, idempotent. Static anycast IP, Google-managed
certificate, HTTP→HTTPS redirect. The serverless NEG is the only regional object;
everything above it is global, which is what lets a Paris-only service sit behind
an anycast address.

**Cost: ~$18–25/month** for the two forwarding rules, against a project otherwise
running ~$10–12/month. Approved by the owner before creation. The alternative —
a Cloudflare Worker rewriting the Host — is free but means operating a proxy to
save $18/month.

**The certificate stays `PROVISIONING` until DNS resolves to the LB**, and in
Cloudflare the record must be **DNS-only**: a proxied record terminates TLS at
Cloudflare, so Google's validation never arrives.

**Done.** Cloud Run accepted public traffic on its `run.app` URL, a second front
door bypassing the LB. Closed with ingress `internal-and-cloud-load-balancing`,
set in `service.yaml` rather than by CLI so the deployed service cannot drift
from the file.

**The ordering was the whole risk.** Cloud Scheduler called the `run.app` URL
directly, so locking ingress first would have stopped the reminder cron
*silently* — the exact failure §5 exists to describe. Sequence actually
followed, each step verified before the next:

1. both jobs repointed at `api.myweli.com` (uri **and** OIDC audience);
2. both fired manually → **200**, proving the new target works;
3. only then the ingress annotation applied;
4. re-verified after: `run.app/health` → **404**, `api.myweli.com/health` and
   `/providers` → **200**, the public site still renders salons, and both cron
   jobs → **200** again.

One trap worth recording: `gcloud run services describe` reports the image of
the *latest* revision template, which after a failed deploy is the **failed**
one. Deploying "the current image" from that value re-deploys a tag that was
never pushed. Read the digest from the revision actually serving traffic
(`status.traffic[0].revisionName`) instead — that also makes the change
surgical, altering ingress and nothing else.

## 8. Verification

- §3.1, §3.2 and §3.3 each watched red before green.
- `dart analyze --fatal-infos --fatal-warnings` = 0; backend suite green.
- **The Q1 funnel smoke run against the deployed Cloud Run service**, not just
  CI's local Postgres. This is the real acceptance gate — **but it cannot run
  against `ENV=prod` as written.** The harness authenticates by reading
  `devCode` off the OTP response (`tool/smoke/funnel_smoke_test.dart:172,201`),
  and production deliberately suppresses it (`auth_repository.dart:224`), so it
  null-casts on the first sign-in. It needs a real mailbox loop or a deliberate
  test seam; decide before relying on it. **Open, and it blocks §6 step 2.**
- `/health` **and** a DB-backed route (`/providers`) both 200 — `/health` alone
  proved nothing during the Render outage, which is the lesson.

## 9. Open questions

1. ~~Is the Render database recoverable, and is any beta data worth exporting?~~
   **Closed — no.** The assumption held: nothing was exported, the cutover ran
   without a `pg_dump` step, and the Render database has since been deleted with
   no loss. There were no real users, which is the whole reason a clean cutover
   was affordable.
2. Cloud SQL tier: smallest shared-core to start (the beta is 15–25 salons), or
   go straight to a small dedicated instance? Recommend shared-core; it is a
   one-command resize with a brief restart.
3. Should `CRON_SECRET` unset become a prod fail-fast in this PR or a follow-up?
   Recommend follow-up, to keep the cutover PR about the move.
4. ~~Delete the Render services immediately after cutover, or keep them a week as
   a rollback?~~ **Closed — kept a week, then deleted.** The week ran
   2026-08-06 → 2026-08-13 and the rollback was never wanted. `render.yaml` is
   removed (§6 step 4, §6.1); git history remains the archive, which is what the
   recommendation meant by "in git history".
