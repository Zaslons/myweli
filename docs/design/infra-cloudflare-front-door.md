# `api.myweli.com` behind Cloudflare — the front door without the load balancer

| | |
|---|---|
| **Status** | Approved 2026-09-09 (owner: « go, write the spec and build it ») · **Built 2026-09-09 — rollout pending, the load balancer serves until §9 step 9** |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-09-09 |
| **PRD ref / phase** | Infrastructure · launch scope (no PRD requirement; a cost decision) |
| **ROADMAP entry** | [2026-09-09-cloudflare-front-door.md](../roadmap/entries/2026-09-09-cloudflare-front-door.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails |
| **Related** | [infra-gcp-migration.md §7.2](infra-gcp-migration.md) (why the LB was chosen) · [backend-rate-limiting.md](backend-rate-limiting.md) (layer 1 / layer 2 — **layer 1 is replaced by this spec, layer 2 is finally wired**) · [backend-identity-rate-limits.md](backend-identity-rate-limits.md) (the limiter this reuses) · [DEPLOYMENT.md](../DEPLOYMENT.md) « What the project actually costs » · [LAUNCH.md §6.5](../LAUNCH.md) (the launch gate this extends) |

## 0. The measurement this answers

Billing → Reports, three settled days (2026-09-05..07), by SKU: **$1.65/day,
≈$50/month**, of which **$26.5/month is two flat network charges** —
`Cloud Load Balancer Forwarding Rule Minimum Global` ($18.26) and Cloud Armor
(policy $5.07 + three rules $3.04 + requests $0.10). They run at zero traffic
and no compute knob touches them. The owner's target is $15–25/month. Without
touching the load balancer the floor is ≈$30 (LB + production Postgres). So:
replace the load balancer, or accept the bill. This spec replaces it.

Re-verified the same day, because the whole case rests on it: Cloud Run domain
mappings are still unsupported in `europe-west9` (the docs list ten regions;
Paris is not one), and Google's own alternative for such regions *is* the
global external Application Load Balancer. The LB was therefore never an
over-build; it was the documented price of a custom domain in Paris. The only
cheaper path is the one [infra-gcp-migration.md §7.2](infra-gcp-migration.md)
named on 2026-08-06 and declined as « operating a proxy to save $18/month »:
a Cloudflare Worker in front of Cloud Run. At $26.5/month, forever, it is now
worth operating.

## 1. Goal & scope

**Goal.** `api.myweli.com` keeps answering exactly as today — for the store
builds that have it compiled in, the two production crons, the two uptime
checks, the web BFF and the admin console — while the global load balancer,
its static IP, its managed certificate and the Cloud Armor policy are
deleted. Steady-state bill ≈$24/month (staging kept) or ≈$13 (staging
deleted, a separate decision); launch week ≈$44 instead of ≈$70.

**How.** Three parts, each load-bearing:

1. **A Cloudflare Worker** on `api.myweli.com/*` forwards every request to the
   Cloud Run `*.run.app` hostname (the Host header follows the URL — that is
   the « Host rewrite » the migration doc asked for) and adds one secret
   header.
2. **An origin gate in the backend**: once production ingress opens to `all`
   (it must — nothing else can reach `run.app`), the direct `run.app` door is
   public again. A middleware refuses every request that does not carry the
   secret header, except `/health`. This is the control that makes the edge
   rate limit un-bypassable, and it replaces what `ingress:
   internal-and-cloud-load-balancing` did.
3. **Per-IP rate limiting on `/auth/*` and `/admin/auth/*`, in two layers**:
   the app's Postgres limiter keyed on the client IP Cloudflare reports
   (`CF-Connecting-IP`, trusted **only after** the origin gate passed), at
   Cloud Armor's numbers (10/minute per IP); and a Cloudflare free-plan
   rate-limiting rule at the edge (one rule, per IP, 10-second window) that
   stops a burst before it reaches Cloud Run or Postgres.

**In scope.** Backend middleware + tests + contract; the Worker and its
provisioning script; the retire script for the LB stack; the manifest change
(ingress, secret, mode); the alert that retires and the one that takes over;
every document and comment that currently says « DNS-only » or « run.app 404s
by design »; the LAUNCH.md §6.5 re-apply list the owner asked for.

**Out of scope, named so it is not forgotten.** Staging stays exactly as it
is (`ingress: all`, no Worker, no secret — §5.6). The web BFF still forwards
no browser IP, so all web visitors share Vercel's egress address in the
per-IP bucket — the status quo under Cloud Armor, a launch item (§11).
Workers Paid ($5/month) if a day ever nears 100 000 requests — a launch item.
Narrowing the 2026-06-29 Pages token (LAUNCH.md) — unrelated credential.
Deleting the staging database — a separate owner decision.

**Fit.** Infrastructure stays idempotent shell (§4.3 of the migration doc), the
backend change is one root middleware + one pure config resolver in the
`boot_config` idiom, and the limiter is the existing `RateLimiter` behind
`FailOpenRateLimiter`. No new layer, no new table.

## 2. UX & flows

No user-facing surface changes. One visible difference: a client that trips
the per-IP limit used to receive Cloud Armor's **HTML** 429 page; it now
receives the house envelope `{"error":"rate_limited"}`. Both apps already
treat any 429 on the OTP screens as « réessayez plus tard » and map
`otp_resend_limit` specifically; `rate_limited` falls into the generic
branch — verified by reading the mobile error mappers before shipping, and
nothing new to translate.

## 3. API & contract

No endpoint, DTO or path changes. Two error responses become possible where
they were not documented:

| Where | Status · code | When |
|---|---|---|
| Every route except `/health` (any method — the route itself answers 405 to non-GET) | **403 `origin_required`** | `ORIGIN_AUTH_MODE=enforce` and the request lacks a correct `X-Myweli-Origin-Auth` header — i.e. it did not come through the Worker |
| `/auth/*`, `/admin/auth/*` (20 paths) | **429 `rate_limited`** | more than 10 requests in the current minute from one client IP |

`openapi.yaml`: `RateLimited` is added to the 14 auth paths that lack it
(only the four `otp/request` routes and the two admin ones document 429
today); `origin_required` is documented once, in the shared `Error` schema
description, since it can appear on any path. `Retry-After` is deliberately
absent, as for every other limiter here.

**Headers this contract now depends on** (inbound, at the origin):

| Header | Set by | Trusted when |
|---|---|---|
| `X-Myweli-Origin-Auth` | the Worker, from its `ORIGIN_AUTH_SECRET` binding | compared constant-time to the origin's `ORIGIN_AUTH_SECRET` |
| `CF-Connecting-IP` | **Cloudflare itself** on every Worker subrequest to a non-Cloudflare origin (« the Worker cannot alter it ») | **only after** the origin gate passed on the same request |

Everything else (`Authorization`, `Origin`, `Content-Type`, `X-Request-Id`,
`X-Smoke-Secret`, `X-Twilio-Signature`, `X-Messaging-Secret`) passes through
the Worker untouched. Cron OIDC checks `aud` against the **configured**
`CRON_OIDC_AUDIENCE` (`https://api.myweli.com`), never the Host, so the Host
following the `run.app` URL is invisible to it.

## 4. Data model

No migration. The existing `identity_rate_limits` table (migration `0034`)
gains buckets of the shape `ip:auth:<sha256(ip), first 32 hex>`. Two things
the identity-limits design demands of an open-set key are honoured:

- **A bounded key**: the IP is hashed, so the column holds a 32-character
  digest whatever the client sends, and no address is stored in clear.
- **A pruner**, because every new IP writes a row: `PostgresRateLimiter.prune(olderThan)`
  deletes `window_start < now() − olderThan` under the limiter's 2 s query
  deadline (the existing guard « every limiter query carries a deadline » went
  red when the prune was first written without one, and was right: a wedged
  Postgres would otherwise hold the cron for Cloud Run's 300 s); called once a
  day from the subscriptions cron **next to `pruneAdminLoginThrottle`** (same route, same
  reason recorded there: a prune nobody can see is the shape this repo keeps
  finding), with `olderThan = 1 day`. Nothing reads a window older than its
  own length (1 h for identity buckets, 1 min for IP buckets), so the retention
  is generous by design.

## 5. Architecture & patterns

### 5.1 Request path, after

```
client ──TLS──▶ Cloudflare edge (proxied A record, rate-limit rule)
                 └─ Worker myweli-api-front-door  (route api.myweli.com/*)
                      └─ fetch https://myweli-api-5a24ymhbbq-od.a.run.app/<path>
                         + X-Myweli-Origin-Auth: <secret>
                         (Cloudflare adds CF-Connecting-IP, CF-Ray, CF-Worker)
                            └─ Cloud Run myweli-api  (ingress: all, invoker: allUsers)
                                 └─ observability → ORIGIN GATE + per-IP limit → query-sanity → CORS → providers → route
```

The direct door — `https://myweli-api-5a24ymhbbq-od.a.run.app` and its older
alias `myweli-api-731308991240.europe-west9.run.app` — is reachable and
answers **403 `origin_required`** to everything but `/health`.

### 5.2 Backend — `lib/src/security/origin_auth.dart` (config) and `origin_front_door.dart` (middleware)

**Config, resolved once at boot, pure and testable** (the `boot_config` idiom:
raw strings in, decision out, so production's fail-fast can be exercised in a
test without touching `Platform.environment`):

```dart
sealed class OriginAuth {}
final class OriginAuthOff implements OriginAuth {}          // dev, CI, staging
final class OriginAuthOn implements OriginAuth {
  final String secret; final OriginAuthMode mode;           // log | enforce
}
enum OriginAuthMode { log, enforce }
const int kMinOriginAuthSecretLength = 32;

OriginAuth resolveOriginAuth(String? secret, String? mode, {required bool isProd});
```

Rules, each a named test:

| Input | Result |
|---|---|
| secret unset/blank, not prod | `OriginAuthOff` — the middleware is inert (staging, dev, CI's `ENV=dev` jobs) |
| secret unset/blank, **prod** | **`StateError` naming `ORIGIN_AUTH_SECRET`** — once the LB is gone, an unset secret in production is an open door, and « an unset value is what the guards exist to catch » (ci.yml) |
| secret present, `< 32` chars | `StateError` — unlike `SMOKE_OTP_SECRET`, where « too short » means « feature off » (safe), here « too short » means « door open » (unsafe), so it refuses in every environment |
| mode unset | `enforce` — the safe default; `log` must be written down in the manifest to exist |
| mode ∉ {`log`, `enforce`} | `StateError` (the `Env.parse` rule: an unknown spelling never silently means something) |

Wired in `dependencies.dart` as `final OriginAuth originAuth = …` and **added
to `_assertConfiguredDependenciesResolve()`** so a mis-set value dies at boot
in one aggregated line, never on the first request.

**The middleware** — one factory taking callbacks (the `corsMiddleware` rule:
the chain is built before the entrypoint runs, a value would pre-empt the
aggregated boot check):

```dart
Middleware originFrontDoorMiddleware(
  OriginAuth Function() config,
  RateLimiter Function() limiter,
  {void Function(String) log = print},
)
```

Per request, in order:

1. `path == '/health'` → pass. Path-**exact**: Cloud Run's liveness probe
   GETs `/health` with no header every 30 s (`service.yaml` `livenessProbe`),
   and the deploy verify step curls it; a prefix match would exempt
   `/healthz-anything`.
2. `config is OriginAuthOff` → pass.
3. Read `x-myweli-origin-auth`. Present and `constantTimeEquals(secret)` →
   **verified**. Otherwise print `origin_auth_missing method=<m> path=<p>`
   (path only, never the query, never any header value — the request-id
   middleware's own rule) and: `mode == log` → pass, unverified; `enforce` →
   **403 `origin_required`**.
4. **Only if verified** and `path.startsWith('/auth/') || path.startsWith('/admin/auth/')`
   (Cloud Armor's two expressions, verbatim): `ip = cf-connecting-ip`. Absent →
   print `origin_client_ip_missing path=<p>` and pass — the identity-limits
   rule that « unknown must never silently collapse into one shared bucket ».
   Present → `limiter.hit('ip:auth:<digest>', limit: 10, window: 1 min)`;
   refused → print `rate_limited bucket=ip:auth:<digest> hits=<h> limit=10`
   and **429 `rate_limited`**. No 80 % warning line for IP buckets — 8 of 10
   in a minute is a human double-tapping, not a signal.

Why the IP is read only after verification: on the direct door anyone can
send `CF-Connecting-IP: 1.2.3.4`; behind the gate the header was set by
Cloudflare on a subrequest the Worker cannot alter (Cloudflare's
documentation: « the CF-Connecting-IP and x-real-ip headers will both reflect
the client's IP address, with only the x-real-ip header able to be
altered »). Verification-before-trust is what lets layer 2 finally enforce
without the `X-Forwarded-For` depth measurement §4 of the rate-limiting design
was waiting for: the key is verified **by construction**, not by measurement.
`clientIpFrom` (the XFF-depth resolver) stays as it is — unwired — and its
header comment is corrected to say so.

**Placement** in `routes/_middleware.dart`: the `.use` immediately before
`observabilityMiddleware` — inside observability so a refusal carries a
request id and is logged and reported; outside CORS, query sanity and every
provider so nothing downstream runs for a request that did not come through
the door. Preflights: the Worker adds the header to **every** method, so an
`OPTIONS` from `admin.myweli.com` carries it and reaches the CORS middleware
as today.

**Fail-open, stated.** `rateLimiter` is `FailOpenRateLimiter(Postgres…)`. A
Postgres blip therefore removes the app-side per-IP bound. This costs nothing
new: every `/auth/*` route already needs Postgres to do its work (OTP
storage, resend counters), so a request that the limiter waves through in
that state fails a few lines later anyway; and the Cloudflare rule remains at
the edge regardless of Postgres.

**Two log lines, and what watches them.** `rate_limited bucket=` already
drives `92-identity-limit-alert.sh` (bare-prefix filter) — the runbook gains
the `ip:auth:` shape (its example lines are pinned by `alert_runbooks_test`
to strings the code prints). `origin_auth_missing` is **not** alerted: during
the log-mode window it is the measurement (§9, step 6), and after enforcement
a scanner hitting `run.app` is noise by definition — it is queried, not paged.

### 5.3 The Worker — `infra/cloudflare/worker/api-front-door/`

Plain JavaScript, no build step (`wrangler` deploys `.js` directly), ~30 lines:

```js
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    url.hostname = env.ORIGIN_HOST;                 // Host follows the URL — the rewrite
    const headers = new Headers(request.headers);
    headers.set('X-Myweli-Origin-Auth', env.ORIGIN_AUTH_SECRET);
    return fetch(new Request(url, {
      method: request.method, headers, body: request.body,   // streamed
      redirect: 'manual',                                      // 3xx returned as-is; never follows with Authorization
    }));
  },
};
```

`wrangler.toml`: `name = "myweli-api-front-door"`, `main = "src/index.js"`,
`compatibility_date`, `[vars] ORIGIN_HOST = "myweli-api-5a24ymhbbq-od.a.run.app"`
(the `status.url` form, read back from the service the way the staging deploy
does), `[[routes]] pattern = "api.myweli.com/*", zone_name = "myweli.com"`.
The secret is **never** in the file: `gcloud secrets versions access … |
wrangler secret put ORIGIN_AUTH_SECRET` (wrangler reads stdin when piped).

Also done, beyond the sketch: a request arriving over `http://` is answered
**301 to `https://` on the public hostname** (the load balancer's redirect
url-map did this; proxying it in clear would let Cloud Run answer 301 naming
its own `run.app` hostname, which the client would follow to the direct door —
found in review); a missing `ORIGIN_AUTH_SECRET` or `ORIGIN_HOST` binding
answers 500 `front door misconfigured` rather than forwarding bare;
`workers_dev = false` so the Worker has no `*.workers.dev` hostname of its own.

What is deliberately **not** done: no Host header set (a cross-zone Host cannot
be forced and the runtime derives it); no `Content-Length` copied (the runtime
sets it and ignores a manual value); no body read (streaming and compression
pass through untouched); no extra client-IP header (Cloudflare sets
`CF-Connecting-IP` itself and the Worker cannot alter it — one fewer thing to
trust).

**Limits, measured against today's traffic.** Workers Free: 100 000
requests/day, reset midnight UTC, **Error 1027 beyond**; production sees
4 800–12 000/day. CPU 10 ms per request, wall-clock time waiting on `fetch`
excluded — a header-only proxy is well inside. Request body cap 100 MB (Free
zone plan); no response cap. **Fail mode past the daily cap is a per-route
dashboard toggle**; this Worker is security-critical, so the runbook sets
**« Fail closed »** (the documented recommendation) and records it — the
default is not stated in the docs (§11).

### 5.4 The Cloudflare zone — `infra/cloudflare/96-api-front-door.sh`

Runs on the owner's machine, reads **one** token from Secret Manager
(`CLOUDFLARE_FRONT_DOOR_TOKEN`, minted in the dashboard — Cloudflare does not
let a token create a token; scope in §6.3), exports it as
`CLOUDFLARE_API_TOKEN` for `wrangler` and `curl`, never prints it, and reads
its work back after every step (the R2 script's rule: a step that aborted
« loudly, to a terminal nobody was reading » is the failure it was written
against). Idempotent — safe to re-run at launch. Steps:

1. **Precheck the zone's SSL mode** (`GET /zones/{id}/settings/ssl`): must be
   `full` or `strict`. `flexible` loops against an HTTPS-redirecting origin
   (the LB redirects 80→443, and while the proxied record still points at it
   the fail-open path goes there). Refuse to continue otherwise.
2. **Report** `security_level` and `browser_check` — Browser Integrity Check
   and Bot Fight Mode can challenge non-browser clients; Google's uptime
   probes, Cloud Scheduler, Vercel's build fetch and the Dart HTTP client
   cannot answer a challenge. The values are printed for the cutover
   checklist; step 8 of §9 proves each client end-to-end.
3. **Deploy the Worker** (`wrangler deploy`), then **put the secret** from
   Secret Manager via stdin, then read back `wrangler deployments list`.
4. **DNS**: `PATCH` the `api.myweli.com` A record to `proxied: true`, content
   unchanged (`8.232.126.191`, the LB — a fail-open target that still serves
   the hostname with a valid certificate until the LB is retired; afterwards
   the retire script's follow-up sets it to the documented originless
   placeholder `192.0.2.0`). Read back: `dig` must now return Cloudflare
   addresses, and a GET of `https://api.myweli.com/health` must carry `cf-ray`
   (a GET with captured headers — `/health` answers 405 to HEAD, so `curl -sI`
   can never pass; found in review).
5. **Rate-limit rule**: `GET …/rulesets/phases/http_ratelimit/entrypoint`; if
   it exists and holds any rule whose description is not ours, **refuse**
   (`PUT` replaces the whole list — never clobber a rule the owner made by
   hand); else `PUT` one rule:
   `starts_with(http.request.uri.path, "/auth/") or starts_with(http.request.uri.path, "/admin/auth/")`,
   characteristics `["cf.colo.id","ip.src"]` (`cf.colo.id` is mandatory via API),
   `period 10`, `requests_per_period 10`, `mitigation_timeout 10`, `action block`.
   Free-plan fields are Path and Verified Bot only, so no `http.host` clause —
   the prefixes are served by nothing else on the zone. Read back the rule id.
   **Whether the Free plan accepts a function or an `or` in the expression is
   UNVERIFIED in the docs** — this step is the proof, and the script fails
   loudly if the API rejects it.

Numbers, and why: Cloud Armor was 10/minute with a 300 s ban. The Free plan
gives a 10 s window and a 10 s block, and its counters are per data centre
and imprecise — so the edge rule is **burst protection** (a 23/s attacker is
blocked after its 10th request in the first second) and the app limiter is
the **authoritative** 10/minute. Not 5 per 10 s: the web BFF's shared egress
address must not be blocked by two visitors requesting codes at once.

### 5.5 Retiring the LB — `infra/gcp/71-retire-load-balancer.sh`

Numbered next to the `70` it undoes. Refuses to run unless `CONFIRM=retire`,
and **reads before it deletes** (the PITR-purge lesson): prints every
resource it is about to remove with its live state, then requires three
observations, each of which would be false if the cutover were incomplete:

- `dig +short api.myweli.com` returns no `8.232.126.191` (the record is
  proxied);
- a GET of `https://api.myweli.com/health` is 200 **and** carries `cf-ray`;
- the direct door answers **403 `origin_required`** on `/providers` and 200 on
  `/health` — proof that enforcement is live, so deleting the LB removes no
  protection.

Then, in reverse-reference order: forwarding rules → target proxies → URL
maps → detach the security policy → backend service → NEG → managed cert →
static address → security policy → the `Cloud Armor REFUSED a request` alert
policy (looked up by display name, the `93-sync-runbooks.sh` idiom). Never the
« Owner email » channel, which every other alert shares. Ends by printing the
two follow-ups it cannot do itself: the DNS placeholder, and the console SKU
rows that must disappear the next day.

`70-load-balancer.sh`, `87-…`, `89-…`, `91-…` are **kept, with a RETIRED
banner** naming this spec: they are the launch-time re-application path the
owner asked to keep (§9.5), and `launch_doc_test` pins that the paths
LAUNCH.md names still resolve. `policy-bodies.sh` drops the `91` line while
the policy is retired (`93-sync-runbooks.sh` exits 1 on a rendered policy with
no live twin); the re-apply list says to put it back.

### 5.6 The manifests

`infra/gcp/service.yaml` (production):

- `run.googleapis.com/ingress: all` — with the comment block rewritten: the
  second front door is now closed **by the origin gate**, not by ingress, and
  the ordering warning becomes the mirror image (open ingress *before* DNS
  moves, keep the LB *until* enforcement is proven).
- `ORIGIN_AUTH_MODE: log` in phase A, `enforce` in phase B (§9).
- `ORIGIN_AUTH_SECRET` → `secretKeyRef: { name: ORIGIN_AUTH_SECRET, key: '1' }`,
  production only (the `WEB_DEPLOY_HOOK_URL` precedent).

`infra/gcp/service-staging.yaml`: **untouched.** Staging is `ingress: all`
with `allUsers` and has been public since it existed; its previews, its
crons, the funnel gate and three alert proof-steps all call its `run.app` URL
without a header. With no secret set the middleware is `OriginAuthOff` there,
and the per-IP limiter is therefore inert on staging — §6.1 of the
rate-limiting design (« layer 2 covers staging once enforcing ») stays false,
and says so now instead of implying otherwise.

Pins added to `service_files_test.dart`: prod ingress is `all` (with the
reason), staging ingress is `all`, `ORIGIN_AUTH_SECRET` is mounted in prod
only and pinned to a numeric key, `ORIGIN_AUTH_MODE` ∈ {`log`, `enforce`}, and
staging declares **no** `ORIGIN_AUTH_*` at all. The file's header claim that
it « asserts ingress differs » — false today, the test never read the
annotation — is replaced by the assertions.

## 6. Security & authz

### 6.1 Threat-model delta (docs/BACKEND.md §7)

| # | Surface | Threat (STRIDE) | Mitigation | Status |
|---|---|---|---|---|
| **T70** | The direct `*.run.app` door, reopened (`ingress: all`, `allUsers` invoker) so that Cloudflare can reach the service | **E/T** — anything that reaches the origin without passing the edge bypasses the edge rate limit and could forge `CF-Connecting-IP`, turning the per-IP limiter into a per-attacker-chosen-key limiter | **The origin gate**: every request but `/health` must carry `X-Myweli-Origin-Auth` equal (constant-time) to a ≥32-char secret only the Worker and the origin hold; production **refuses to boot** without it; the default mode is `enforce`, and `log` exists only as a written, bounded rollout state (§9). `CF-Connecting-IP` is read **after** the gate, never before. A forged header on the direct door is answered 403 before any limiter runs. **Residual:** the secret is a bearer credential shared by two systems; rotation needs a `log` window (§6.2). The `/health` exemption reveals that a service exists at the alias — public information already. | Implemented (this slice) |
| **T71** | `/auth/*` and `/admin/auth/*` per-IP limiting, now in the app | **D** — an attacker rotating identifiers is bounded per source address at 10/minute (T65's « bounded by Cloud Armor's 10/min » becomes « bounded by this row ») | Postgres limiter keyed on `ip:auth:<sha256>` behind the gate; Cloudflare rule at the edge (per IP, 10 per 10 s, block 10 s) so a burst never reaches Postgres. **Residual:** shared egress collapses many humans into one bucket — the web BFF forwards no browser IP, so every web visitor shares Vercel's address (status quo under Cloud Armor; launch item §11); distributed attackers pay one address per 10 req/min (unchanged); edge counters are per data centre (documented) — the app limit is the precise one. | Implemented (this slice) |

T65 and T66 lose the sentences that are now false (« bounded by Cloud Armor's
10/min per IP on `/auth/*` », « `api.myweli.com` is DNS-only by design so
Cloudflare is not in the request path ») and point here. T21 keeps its
evidence (OIDC through the LB) with a dated note that the same proof is
repeated through the Worker in §9 step 8.

### 6.2 Secrets

- `ORIGIN_AUTH_SECRET`: 64 base64url characters from `openssl rand -base64 48 | tr -d '\n=' | tr '+/' '-_'`
  (the `90-staging.sh` generator), written **once** with `printf '%s' | gcloud
  secrets versions add --data-file=-`, never echoed; `secretAccessor` granted
  to `myweli-run@`; pinned `key: '1'` and watched by
  `98-verify-secret-pins.sh` like every other pin. The Worker receives it by
  stdin pipe. **Rotation**: set `ORIGIN_AUTH_MODE=log` + deploy (the origin now
  accepts both the old header and none); `versions add` v2 + manifest `key: '2'`
  + `wrangler secret put` v2 + deploy; back to `enforce` + deploy. Written in
  DEPLOYMENT.md next to « Changing a secret, in order ».
- The header value is never logged: the request middleware logs
  method/path/type only, and Sentry empties every request header before an
  event leaves the process (`observability_test.dart`).
- `CLOUDFLARE_FRONT_DOOR_TOKEN` (§6.3) lives in Secret Manager and is read on
  the owner's machine. **CI never reads it** — `production-checks.yml` asserts
  CI cannot read *any* secret value, and the Worker is not a CI deploy (the
  R2 stance: « CI has no Cloudflare identity » stays true).

### 6.3 The one Cloudflare token (owner mints it; dashboard only)

Custom token, scoped to **zone `myweli.com`** only, **no R2, no Pages**:
Account → *Workers Scripts: Edit* · *Account Settings: Read* · User → *User
Details: Read* (what `wrangler` needs to deploy) · Zone → *Workers Routes:
Edit* · *DNS: Edit* · *Zone WAF: Edit* (the rate-limiting rule; the docs spell
it « Write » in one place and « Edit » in another — same permission) · *Zone
Settings: Read* · *Zone: Read*. Stored with
`pbpaste | gcloud secrets create CLOUDFLARE_FRONT_DOOR_TOKEN --project myweli --replication-policy=automatic --data-file=-`
— the exact gesture used for `SENTRY_AUTH_TOKEN`.

## 7. Performance

- Origin gate: one header lookup and a constant-time compare of 64 chars —
  microseconds, every request.
- Per-IP limit: **one Postgres upsert per `/auth/*` request** (2 s query
  timeout, fail-open). Cloud Armor did this for free at the LB; the trade is
  accepted because the OTP routes already write to Postgres and the edge rule
  absorbs bursts. Measured after cutover: `/auth/email/otp/request` p50 before
  vs after, from the uptime series and one timed burst.
- One extra hop: client → Cloudflare PoP → Paris. The uptime checks' latency
  series (`/health`, `/providers`) is the before/after instrument; budget
  **+50 ms p50** or the decision is revisited. Bodies stream; nothing is
  buffered in the Worker.
- No cold-start change; `minScale` untouched.

## 8. Testing plan

**Unit — `resolveOriginAuth`** (pure): the five rows of §5.2 each as a test,
plus the dev pair for every refusal (`isProd: false` with the same input must
*not* throw where the rule is prod-only) so « always throw » cannot pass.

**Middleware — `origin_front_door_test.dart`** (mocktail, `inner.use(...)`
idiom; a recording `inner` and a recording `log`):

1. `/health` without header, `enforce` → passes, inner ran. Control:
   `/healthz` → 403.
2. `OriginAuthOff` → passes, no log.
3. `enforce`, no header → 403 `{error: origin_required}`, inner **not** run,
   log line `origin_auth_missing method=GET path=/providers` (and the query
   string is absent from it).
4. `enforce`, wrong value (same length, one char off) → 403.
5. `enforce`, right value → passes.
6. `log`, no header → passes **and** logs; `log`, right value → passes, no log.
7. `OPTIONS /appointments` with the header → passes (preflights carry it).
8. Spoof: `enforce`, no origin header, `CF-Connecting-IP: 1.2.3.4` on
   `/auth/otp/request` → 403 and the limiter was **never called**.
9. Verified, `/auth/otp/request`, `CF-Connecting-IP: 203.0.113.9`: 10 calls
   pass, the 11th → 429 `{error: rate_limited}` and the log line
   `rate_limited bucket=ip:auth:<digest> hits=11 limit=10`; a different IP is
   still at 1/10; `/providers` from the same IP never touches the limiter;
   `/admin/auth/login` shares the scope; the digest is not the IP.
10. Verified, no `CF-Connecting-IP` → passes, logs `origin_client_ip_missing`,
    limiter never called.
11. Limiter throws → request passes (fail-open is the wrapper's job, but the
    middleware must not turn a limiter error into a 500).
12. Window: with a fake clock, the 11th request in the next minute passes.

**Source-level wiring pins** (the `identity_limits_wiring_test` shape):
`routes/_middleware.dart` uses `originFrontDoorMiddleware` and it appears
*after* `querySanityMiddleware()` and *before* `observabilityMiddleware`;
`dependencies.dart` constructs `originAuth` from the two env names and lists
it in `_assertConfiguredDependenciesResolve`; the header name string is
identical in `origin_front_door.dart` and `worker/api-front-door/src/index.js`
(comments stripped); the Worker sets `redirect: 'manual'` and never sets a
`host` header; `wrangler.toml` routes `api.myweli.com/*` on `myweli.com` and
holds no secret; `71-retire-load-balancer.sh` contains `CONFIRM` and no
`create`; `96-api-front-door.sh` checks the ruleset before any `PUT` and never
prints the token; the runbook example lines in `92` match a printed string.

**Manifests**: the pins of §5.6, and the existing shared-secret,
numeric-key and placeholder pins stay green.

**Contract**: a test that every path under `/auth/` and `/admin/auth/` in
`openapi.yaml` documents 429.

**CI, a branch a plain test run cannot reach**: a new `ci.yml` step boots the
real binary with `ENV=prod`, a fake ≥32-char secret and `enforce`, and proves
`/health` 200 without header, `/providers` 403 without, 200 with, 403 with a
wrong one — then boots with a 9-char secret (`too-short`) under `timeout` and requires the
process to die naming `ORIGIN_AUTH_SECRET` (124 is a failure of the subject).
The two existing `ENV=prod` jobs gain the fake secret (they « rehearse the
configuration production has »); the Q1b job also sets `ORIGIN_AUTH_MODE: log`
because its curls carry no origin header by design.

**Mutations, watched red on committed work** (each names the test that must
fail): `==` instead of constant-time · exemption widened to `startsWith('/health')` ·
IP read before verification · `enforce` default flipped to `log` · short-secret
refusal removed · prod-absent refusal removed · limit 10 → 100 · scope loses
`/admin/auth/` · digest replaced by raw IP · Worker header renamed on one side ·
`redirect: 'manual'` removed · `71` loses its `CONFIRM` guard · `96` PUTs
without the ownership check.

**Acceptance on the live path** (§9 step 8) is scripted, not narrated:
`infra/gcp/72-verify-front-door.sh`, read-only — the 87/89 burst probe (15
POSTs → ≥1 non-429 then 429s **with a JSON body**), the `/health` control
burst (15 × 200), the direct door (403/200), `cf-ray` presence, a forced cron
run → 200, both uptime checks passing, an `OPTIONS` preflight from
`https://admin.myweli.com` returning the CORS headers, and a request with the
Dart client's User-Agent returning 200 (the Browser Integrity Check question).

## 9. Rollout — ordered, gated, reversible at every step

Every step marked **[owner]** is a cloud mutation and waits for the owner's
word. Nothing before step 3 changes what serves traffic.

1. **This PR** (code + docs + scripts + manifest with `ORIGIN_AUTH_MODE: log`).
   CI green; mutations watched red.
2. **[owner]** Create `ORIGIN_AUTH_SECRET` (generated, never printed; IAM to
   `myweli-run@`) and store `CLOUDFLARE_FRONT_DOOR_TOKEN`. **Before the
   merge** — the staging deploy that a merge triggers runs
   `98-verify-secret-pins.sh` over *both* manifests and fails on a pin whose
   secret does not exist.
3. **Merge.** Staging auto-deploys with the middleware inert (no secret in its
   manifest) — a free proof that `OriginAuthOff` changes nothing.
4. **[owner] Production deploy, phase A**: `ingress: all` + secret + `log`.
   The LB still fronts the hostname; the direct door is open **and counted**
   (`origin_auth_missing`). Verify: `api.myweli.com/health` 200 via the LB;
   `run.app/health` 200 (ingress open); `run.app/providers` 200 with a log
   line (log mode).
5. **[owner] `96-api-front-door.sh`**: SSL precheck, Worker, secret, proxied
   DNS, rate rule. From here `api.myweli.com` traffic goes edge → Worker →
   origin with the header; the LB is idle but alive.
6. **Measure, not assume** — the log-mode window's purpose:
   `gcloud logging read 'textPayload:"origin_auth_missing"'` over the window
   must show only direct-door probes (paths and counts), **none** from the
   Worker path; and `CF-Connecting-IP` for a request from this machine equals
   this machine's public address (the discriminating check: a request through
   the LB has no such header). Target: same day.
7. **[owner] Production deploy, phase B**: `enforce`. Verify the direct door
   now answers 403 on `/providers` (both aliases) and 200 on `/health`.
8. **`72-verify-front-door.sh`** — the acceptance of §8, including a forced
   `myweli-reminders` run (the cron path staging cannot rehearse, because its
   audience is its own `run.app`) and the Vercel production build's
   `/localities` fetch (redeploy the web once and watch the build log).
9. **[owner] `71-retire-load-balancer.sh`** with `CONFIRM=retire`, then the DNS
   placeholder. Next day: Billing → Reports shows no forwarding-rule and no
   Cloud Armor rows.
10. Docs finalised with the measured numbers; roadmap entry; §6.5 list.

**Rollback per phase.** Before 5: nothing to undo. After 5, before 7: set the
A record back to DNS-only — the LB still answers within one TTL. After 7: set
`ORIGIN_AUTH_MODE=log` and deploy. After 9: `70-load-balancer.sh` (new IP →
DNS-only A record → certificate `PROVISIONING` until DNS resolves → `87`, `89`,
`91` → lock ingress) — tens of minutes, and the reason the LB is kept alive
until enforcement is proven.

### 9.5 The launch gate — what to re-apply, and what to decide (LAUNCH.md §6.5)

The owner's instruction: keep a record that at launch « we need to reapply
all of them ». The list, with the honest split between *must* and *decide*:

| At launch | Kind | Where |
|---|---|---|
| `minScale` `'0'` → `'1'` (+ the `service_files_test` pin) | **Must** | already in §6.5 |
| Workers plan: Free (100k req/day, fail closed) → **Paid $5/month** if any day could near the cap; re-check the route's fail mode | **Must decide** before real traffic | §6.5 |
| Web BFF forwards the browser IP (else all web visitors share one auth bucket) | **Must** before real users | §6.5, §11 here |
| **Load balancer + Cloud Armor back?** `70` → DNS-only A record → wait `ACTIVE` → `87` `89` `91` → `ingress: internal-and-cloud-load-balancing` → remove the Worker route → restore the `91` line in `policy-bodies.sh`. +$26.5/month. Buys: 300 s bans, adaptive protection, Google anycast, no Cloudflare dependency. Loses nothing this spec ships unless Cloudflare is removed from the path. | **Decide** — the scripts and this runbook are kept so the answer can be « yes » in an afternoon | §6.5 |
| Re-read the two Cloudflare facts this design leans on (Free = 1 rate rule / IP / 10 s; Workers Free = 100k/day) — plans change | **Must** | §6.5 |
| Staging database, if it was deleted meanwhile | **Must** re-create | §6.5 |

## 10. Definition of done

- [ ] `dart analyze --fatal-infos --fatal-warnings` = 0 · `dart format` clean · backend tests green · web/mobile untouched.
- [ ] Contract (`openapi.yaml`), threat model (T70, T71, T65/T66/T21 edits), ROADMAP entry, `.env.example`, DEPLOYMENT.md, LAUNCH.md §6.5, README index — in the same PR.
- [ ] Every stale « DNS-only / run.app 404s by design » sentence rewritten: `service.yaml`, `service-staging.yaml`, `deploy-backend.yml` (two places), `87`, `89`, `70` banners, `migrations.dart:984`, `client_ip.dart` header, `rate_limiter.dart` header, DEPLOYMENT.md, LAUNCH.md, `infra-staging.md`.
- [ ] Mutations of §8 watched red on committed work; CI step reaches the enforce branch.
- [ ] Rollout §9 executed step by step with the owner's word at each **[owner]**; `72-verify-front-door.sh` green on the live path; console rows gone.
- [ ] Feature branch + PR; no Claude attribution.

## 11. Open questions

1. **Free-plan expression acceptance** — whether the Rulesets API accepts
   `starts_with(...) or starts_with(...)` on Free is not in the docs. Step 5 is
   the proof; if refused, fall back to `http.request.uri.path matches "^/(admin/)?auth/"`
   and, failing that, one prefix (`/auth/`) at the edge with `/admin/auth/`
   covered by the app limiter only.
2. **Fail mode default** — not documented; set « Fail closed » by hand and
   record it in DEPLOYMENT.md; a launch check re-reads it.
3. **Browser Integrity Check / Bot Fight Mode** — reported by `96`, proven by
   `72` (Dart User-Agent, Google probes, Scheduler, Vercel build). If any is
   challenged: a Configuration Rule disabling BIC for the `api` host.
4. **Two `run.app` aliases** — the Worker targets `status.url`; `72` proves
   the older alias also answers 403 after enforcement.
5. **Vercel env** — docs say Production → `api.myweli.com`, Preview → staging
   `run.app`; read back in the dashboard before phase B (a scope holding the
   prod `run.app` would 403).
6. **BFF client IP** — out of scope here, on the §6.5 list: the BFF must send
   the browser address in a header the origin trusts *from Vercel only*, which
   is a second origin-auth relationship, not a header the world may set.
7. **Cloud Armor's 300 s ban** has no Free-plan equivalent; the app limiter's
   fixed minute is the ceiling. Acceptable pre-launch; part of the launch
   decision in §9.5.
