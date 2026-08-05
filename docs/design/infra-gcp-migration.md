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
| dashboard cron jobs (**invisible to the repo**) | Cloud Scheduler, declared in `infra/gcp/` | see §5 |
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

Found while writing the secret checklist (§7): **the backend could not have
booted on Cloud Run at all.** `dependencies.dart:604` refuses to start in
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

Two Cloud Scheduler jobs, declared in `infra/gcp/`:

| Job | Schedule | Target |
|---|---|---|
| `myweli-reminders` | every 15 min | `POST /internal/cron/reminders` |
| `myweli-subscriptions` | daily 03:00 UTC | `POST /internal/cron/subscriptions` |

Both send `X-Cron-Secret` from Secret Manager. **A follow-up should make an
unset `CRON_SECRET` fail fast in prod too** — a 404 that means "silently
disabled" is the same class of defect as §3.1, and it is why nobody noticed the
reminder cron was never running.

## 6. Cutover

1. Ship §3.1, §3.2 and §3.3, green, on `main`. (§3.3 is a hard blocker: without it the service cannot boot in production at all.)
2. Provision GCP (§7), seed, and run the **Q1 funnel smoke against the Cloud Run
   URL** — 47 assertions over real HTTP are exactly the acceptance test for
   "this environment works", and they already exist.
3. Point `api.myweli.com` at Cloud Run.
4. Watch, then delete the Render services and remove `render.yaml`.

No traffic-splitting or dual-run: there are no users yet, so a clean cutover is
simpler and safer than a migration dance.

## 7. Who does what

| Step | Whose |
|---|---|
| `gcloud auth login`, create project, **link billing** | **owner** — needs a browser and a card |
| Enable APIs, Artifact Registry, Cloud SQL, Cloud Run, Secret Manager, Scheduler, WIF | **mine**, once authenticated |
| Supply **11** of the 26 `sync: false` values — auth (Google/Apple client IDs, Resend key, `EMAIL_FROM`), R2 (5), FCM (3) | **owner** — I never see or store them; they go straight into Secret Manager |
| The other 15: 3 minted by me into Secret Manager (§2), 8 Twilio/Termii + `MESSAGING_PROVIDER` **not supplied at all** (§3.3 — messaging off), the rest plain Cloud Run config | — |
| Deploy pipeline, service config, scripts, docs | **mine** |
| DNS for `api.myweli.com` | **owner** |

## 8. Verification

- §3.1, §3.2 and §3.3 each watched red before green.
- `dart analyze --fatal-infos --fatal-warnings` = 0; backend suite green.
- **The Q1 funnel smoke run against the deployed Cloud Run service**, not just
  CI's local Postgres. This is the real acceptance gate.
- `/health` **and** a DB-backed route (`/providers`) both 200 — `/health` alone
  proved nothing during the Render outage, which is the lesson.

## 9. Open questions

1. Is the Render database recoverable, and is any beta data worth exporting? If
   yes, §6 gains a `pg_dump` step. Assumed no until the dashboard says otherwise.
2. Cloud SQL tier: smallest shared-core to start (the beta is 15–25 salons), or
   go straight to a small dedicated instance? Recommend shared-core; it is a
   one-command resize with a brief restart.
3. Should `CRON_SECRET` unset become a prod fail-fast in this PR or a follow-up?
   Recommend follow-up, to keep the cutover PR about the move.
4. Delete the Render services immediately after cutover, or keep them a week as
   a rollback? Recommend keeping the (now paid) database off but the blueprint
   in git history for one week.
