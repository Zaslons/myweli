# Myweli — deployment & accounts runbook

The end-to-end guide to take Myweli live. Domain: **`myweli.com`**. Nothing here
needs secrets in git — every key is set in the host's secret manager. Source of
truth for backend keys: [`backend/.env.example`](../backend/.env.example); for web:
[`web/.env.example`](../web/.env.example).

## 0. What runs where
| Component | Tech | Host | Domain |
|---|---|---|---|
| Backend API | dart_frog (Docker) | **Cloud Run** (`europe-west9`, Paris) — `infra/gcp/service.yaml` | `api.myweli.com` (via a global HTTPS load balancer) |
| Database | PostgreSQL 16 | **Cloud SQL** `myweli-db` (same region), reached through the Auth Proxy sidecar | internal |
| Web | Next.js | **Vercel** | `myweli.com` + `www` |
| Admin console | Flutter Web | static host (Vercel/CF Pages) | `admin.myweli.com` |
| Mobile | Flutter (consumer + pro) | App Store + Google Play | — |
| Object storage | Cloudflare R2 (3 buckets) | Cloudflare | `cdn.myweli.com` (public bucket) |
| Messaging | **off** — `MESSAGING_PROVIDER=disabled` | (Termii is the intended launch provider; Twilio is test-only at $0.49/segment to CI) | webhook → `api.myweli.com` |
| Push | Firebase Cloud Messaging | Firebase | — |
| DNS/CDN | Cloudflare | Cloudflare | `myweli.com` zone |
| Errors | Sentry — **live on all three surfaces**, plus Cloud Monitoring uptime checks | Sentry / GCP | — |

**Stack — built to scale without re-platforming.** Google Cloud (Cloud Run +
Cloud SQL, Paris) · Vercel (web) · Cloudflare R2 (images) + Pages (admin) ·
Twilio (WhatsApp/SMS) · Firebase FCM (push) · Sentry. What protects you from a
forced migration is **standard interfaces** — Docker, the Postgres wire protocol,
the S3 API, Next.js — not the vendor; each piece is individually swappable.

> **This ran on Render first, and the move is worth remembering.** The original
> choice was Render, for one reason: **GCP billing rejected the prepaid/virtual
> cards common in Côte d'Ivoire**, while Render is Stripe-billed. That constraint
> lifted, and the migration was then forced by a different one — the free Render
> Postgres *appeared* to have expired (every database-backed route answered 500;
> the symptom was observed, the cause inferred), so the database had to be
> re-provisioned regardless. Moving both at once cost nothing extra, because the whole point of
> the interfaces above is that the **same `backend/Dockerfile`** runs in either
> place. Design:
> [design/infra-gcp-migration.md](design/infra-gcp-migration.md).
>
> Cutover was **2026-08-06**, Render was deleted a week later, and `render.yaml`
> is gone from the repo — git history is its archive. Alternatives via the same
> interfaces, if a third move is ever wanted: Railway / DigitalOcean / Fly.io
> (backend), Neon / Supabase (DB), Cloudflare Pages (web), Africa's Talking or
> Termii (cheaper CI SMS). Region: **`europe-west9` (Paris)** — marginally closer
> to Abidjan than Frankfurt, same latency class.

No payment gateway: deposits are **no-custody** (salons use their own Wave/MoMo);
Myweli never holds funds.

---

## Phase A — Accounts to open
Domain ✅ (`myweli.com`). Then: **Google Cloud** ✅ (project `myweli` — backend +
Postgres) · Vercel ✅ · Cloudflare ✅ (R2 + DNS + Pages) · Twilio ✅ · Firebase ✅ ·
Sentry ✅ · Apple Developer ($99/yr) ✅ · Google Play ($25 once) · a Myweli business
WhatsApp number.

**Twilio is opened but is not the launch provider, and its tick used to hide that.**
A $26.60 / 54-segment test bill suspended the account — SMS to Côte d'Ivoire is
~62× the US price. **Termii** is the intended channel at ~21× less, gated on
company registration for a branded sender id, and until then production runs
`MESSAGING_PROVIDER=disabled` by decision rather than by omission. See
[design/messaging-termii.md](design/messaging-termii.md).

## Phase B — Provision services
**B1. Postgres (Cloud SQL) ✅ — `myweli-db`, provisioned.** PostgreSQL 16,
`db-f1-micro`, `europe-west9-b`, 10 GiB auto-resizing SSD. Daily backups with 7
retained and point-in-time recovery on a 7-day transaction-log window;
**deletion protection on** and `sslMode: ENCRYPTED_ONLY`.

The backend does **not** hold a public connection string. `DATABASE_URL` points
at `127.0.0.1:5432` and a **Cloud SQL Auth Proxy sidecar** in the same Cloud Run
instance encrypts the hop — chosen over a unix socket because `createPool` builds
from a `host:port` URL, and over private IP because that needs a VPC on day one.
`database.dart` already treats a local host as "no SSL needed", so this was zero
application change. The proxy must be listening before the app runs migrations,
which is what the `container-dependencies` annotation in `infra/gcp/service.yaml`
guarantees — without it the app can reach migrations first and the revision dies.

A **restore has been rehearsed**, not merely configured: 23 minutes wall-clock
from backup to a queryable instance. See
[design/infra-prod-hardening.md](design/infra-prod-hardening.md).

**B2. Cloudflare R2** (specs: pro-image-upload-pipeline / pro-kyc / consumer-deposit):
- Buckets: `myweli-uploads` (public), `myweli-kyc-private`, `myweli-deposits-private`.
- Bind `cdn.myweli.com` to the public bucket.
- Create an R2 API token (access key + secret).
- **CORS** on the public bucket: allow `PUT,POST` from `https://myweli.com` (the
  pro-web photo upload posts directly to R2).
- Keys → `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
  `R2_PUBLIC_BASE_URL=https://cdn.myweli.com`, `R2_KYC_BUCKET`, `R2_DEPOSIT_BUCKET`.

**B3. Twilio** (spec: messaging-notifications): buy a number; enable WhatsApp;
**submit WhatsApp templates for approval early** (confirmation + 24h/2h reminders).
Keys → `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_SMS_FROM`,
`TWILIO_WHATSAPP_FROM`, `MESSAGING_WEBHOOK_SECRET`.

**B4. Firebase/FCM** — the app code is DONE (real `firebase_messaging`, both
apps); what's left is console work. Specs:
[push-notifications-fcm.md](design/push-notifications-fcm.md) (backend) +
[push-notifications-app.md](design/push-notifications-app.md) (app).

1. **Create the Firebase project.** — **DONE.** Firebase is active on the GCP
   project `myweli`, and all four apps are registered (two Android flavors, two
   iOS flavors). Registration and config download were scripted against the
   Firebase Management API rather than clicked; the app ids are in the
   committed config files.
2. **Register TWO Android apps** — one per flavor, matching the applicationIds:
   `com.myweli.app` (consumer) and `com.myweli.pro` (pro).
   **And TWO iOS apps** on the same identifiers, now that iOS has the matching
   flavor split ([mobile-ios-flavours.md](design/mobile-ios-flavours.md)) —
   download each `GoogleService-Info.plist`. Note **nothing Firebase
   client-side exists yet on any platform**: `mobile/` contains no
   `google-services.json` and no `GoogleService-Info.plist`, so push is unwired
   on the client regardless of the FCM server credentials.
3. **Download the two `google-services.json`** and drop each in its flavor's
   source set — create the dir if missing:
   - `mobile/android/app/src/consumer/google-services.json`
   - `mobile/android/app/src/pro/google-services.json`
   Commit them. They are **public client config** (they ship inside the APK) —
   `.gitleaks.toml` already allowlists these paths. The Gradle plugin applies
   itself as soon as a file is present; without them the repo still builds.

   **DONE.** Note the two Android files are byte-identical: Firebase's config
   endpoint returns *every* Android client in the project, and the Gradle plugin
   picks the one matching the flavor's `applicationId` at build time. The
   duplication is inherent to the API, not a mistake — and per-flavor placement
   is what `app/build.gradle.kts:13` actually probes for.

   **iOS is different and needed real work.** `Firebase.initializeApp()` takes no
   options (`firebase_bootstrap.dart:31`), so it reads
   `GoogleService-Info.plist` **from the app bundle** — and unlike Android there
   is no plugin to put it there. The two flavors need *different* files (separate
   Firebase apps, different bundle ids and API keys). So the plists live in
   `mobile/ios/config/{consumer,pro}/` and a run-script build phase, generated by
   `ios/tool/setup_flavours.rb`, copies the right one keyed off `$CONFIGURATION`.
   A flavorless build matches no directory and is skipped — the same "only when
   present" posture as the Gradle wiring. Verified against the BUILT bundle:
   consumer → `com.myweli.app`, pro → `com.myweli.pro`, flavorless → no plist.
4. **Service account** (Project settings → Service accounts → Generate key) →
   **Secret Manager** (the backend moved to Cloud Run — G1). Only
   `FCM_PRIVATE_KEY` is a secret, and it keeps its `\n` escapes
   (`dependencies.dart:650` converts them); `FCM_PROJECT_ID` and
   `FCM_CLIENT_EMAIL` are not secret and live as plain config in
   `infra/gcp/service.yaml`. Never in the repo.
5. **Reminder cron** — Cloud Scheduler job `myweli-reminders`, `POST
   /internal/cron/reminders` every 15 min, OIDC-authenticated (Phase C step 6).
6. **Android smoke test — two real devices** (the first true end-to-end run
   **on device** — the backend funnel is proven in CI since Q1, but nothing had
   run on real hardware against a deployed API;
   there is no Android SDK in CI, so this is where the native build is proven):
   ```sh
   cd mobile
   flutter build apk --debug --flavor consumer -t lib/main.dart   # must build
   flutter build apk --debug --flavor pro      -t lib/main_pro.dart

   flutter run --flavor consumer -t lib/main.dart \
     --dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com
   flutter run --flavor pro -t lib/main_pro.dart \
     --dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com
   ```
   Then walk the story:
   - Book from the consumer → the **pro** device gets « Nouvelle réservation »
     (named channel « Notifications Myweli », `ic_stat_myweli` in the status
     bar) → tap → the booking opens (**switching salon first** if it belongs to
     another of the account's salons).
   - Accept from the pro → the **consumer** device gets « Réservation acceptée »
     → tap → the booking opens.
   - Repeat with each app **killed** (a cold-start tap is buffered, then opens
     once the session restores) and **foregrounded** (Android draws it locally).
   - The pro bell shows the unread badge; `/pro/notifications` lists the feed;
     « Tout lire » clears it.
   - Turn « Notifications push » OFF in consumer prefs → the next event is
     silent, but the in-app feed row still lands (server-side gate).
   - Deny notifications in the OS → the prefs screen shows « Notifications
     désactivées pour l'appareil » → « Ouvrir les réglages » → re-enable →
     return to the app → the banner disappears.
7. **iOS (deferred — needs the Apple developer account).** The code is
   complete but was never compiled. In Xcode: set `CODE_SIGN_ENTITLEMENTS` to
   `Runner/Runner.entitlements`, add the **Push Notifications** capability,
   realign the bundle IDs (`com.example.*` → `com.myweli.app` / `com.myweli.pro`),
   register the two iOS apps in Firebase, add `GoogleService-Info.plist`, and
   upload the **APNs key** to Firebase. Then re-run the smoke test on an iPhone
   (a simulator never receives push).

## Phase C — Deploy the backend (Cloud Run) ✅ — provisioned, and this is how it works

**There is no dashboard step here, and that is the design.** The whole service —
sidecar, secrets, probes, scaling, ingress — is declared in
`infra/gcp/service.yaml` and applied with `gcloud run services replace`. Never
`gcloud run deploy --set-env-vars` by hand: that creates a revision which
silently diverges from the file, and the reason this is stated so firmly is that
the *previous* platform's cron jobs lived in a dashboard, invisible to review,
which is how the reminder cron came to be switched off without anyone noticing.

1. **Deploy** — run `.github/workflows/deploy-backend.yml` from the Actions tab
   (`workflow_dispatch`, type `deploy` to confirm). It authenticates by
   **Workload Identity Federation**, so there is no service-account key in this
   repo or in GitHub secrets: a leaked repo leaks no credential. It builds
   `backend/Dockerfile` for `linux/amd64`, pushes to Artifact Registry, and
   substitutes only the image and the release into the service file.
2. **Secrets** live in **Secret Manager**, mounted by `secretKeyRef` — 18 of
   them, listed in `infra/gcp/service.yaml`. `FCM_PROJECT_ID` and
   `FCM_CLIENT_EMAIL` are public identifiers and stay plain config; only
   `FCM_PRIVATE_KEY` is a secret. Migrations run at boot, serialised across
   instances behind a Postgres advisory lock, **before the port binds**.

   **Adding a version is not the whole procedure, and on its own it changes
   nothing.** Every mount uses `key: latest`, which Cloud Run resolves **when the
   container starts** — and production pins `minScale: '1'`, so the instance does
   not restart on its own. The logs show exactly one container start per
   revision, ever. So:

   ```
   printf '%s' "$NEW" | gcloud secrets versions add <NAME> --data-file=-
   ```

   then **deploy**, so a new revision starts and re-resolves it. `printf` rather
   than `echo`: Dart trims the trailing newline, nothing outside Dart does.
   Confirm the serving revision name actually changed — a deploy at an unchanged
   commit renders a byte-identical manifest and creates no revision at all, which
   looks green and re-resolves nothing. Only once the new value is serving should
   the superseded version be disabled.

   This bit us: `ADMIN_PASSWORD` v2 was added 2026-08-21 and the instance ran for
   two days on v1, which by then was disabled — a value matching no enabled
   version. Harmless only because the admin seeder is insert-only. The same drift
   on `JWT_SECRET`, under `maxScale: 4`, is some instances signing with the new
   key while others verify with the old.
3. **A revision missing a required value never serves.** Every `guardsOn`
   fail-fast fires during startup rather than on first use, so a deploy missing a
   secret fails loudly instead of going green and 500-ing per feature later.
   **Note the narrowness — it is "missing", not "misconfigured".** The guards
   test whether a value is *absent*; a value that is present and wrong passes
   every one of them and serves. This sentence used to say "misconfigured", which
   claimed a great deal more than the mechanism delivers
   ([BACKEND.md §3.2.2](BACKEND.md)). The workflow's verify step then asserts the
   serving image is the one just built, that `/health` and a database-backed
   route answer, and that the service **reports the environment it was asked to
   deploy**.
4. **`api.myweli.com` is a global HTTPS load balancer, not a domain mapping** —
   Cloud Run domain mappings are unimplemented in `europe-west9`. The service
   sets `ingress: internal-and-cloud-load-balancing`, so the `*.run.app` URL 404s
   by design and the load balancer is the only front door. Built by
   `infra/gcp/70-load-balancer.sh`.
5. **Twilio webhook — not applicable yet**, listed so it is not forgotten when
   messaging turns on. Production runs `MESSAGING_PROVIDER=disabled` and mounts
   no Twilio credentials, so nothing calls this route today. When a provider is
   configured, the status callback is
   `https://api.myweli.com/webhooks/messaging/status` — **no query string.**
   Twilio authenticates its own callbacks with `X-Twilio-Signature`, verified
   against `TWILIO_AUTH_TOKEN`, so there is no secret to append. Appending one
   would also *break* verification: Twilio signs the URL as configured, query
   string included, so a callback registered with `?secret=…` would fail every
   signature check. Turning Twilio on therefore needs **`PUBLIC_BASE_URL` set as
   well** — without it there is no URL to reconstruct and the webhook 404s
   (BACKEND.md §7 T19).
6. **Crons are Cloud Scheduler jobs**, not dashboard entries: `myweli-reminders`
   every 15 min and `myweli-subscriptions` daily at 03:00 UTC, both authenticated
   with a Google-signed OIDC token (`myweli-scheduler@`). A transitional
   `X-Cron-Secret` header is still accepted and was to be retired once real runs
   were seen on the OIDC path. **That condition is now met, twice over
   (2026-08-17)** — see
   [design/infra-cron-oidc-evidence.md](design/infra-cron-oidc-evidence.md):
   staging's jobs carry **no** shared secret and answer 200 (while anonymous
   callers get 403), and production has run **251 consecutive cron requests on
   revision `-00017-p4j` with zero `cron_auth_legacy`** log lines. **The header was retired on 2026-08-18** — both
   jobs stripped one at a time (each forced afterwards: 200, no fallback), then
   the code, then `CRON_SECRET` out of every manifest. OIDC is now the only cron
   auth, so a broken audience fails closed; the alert moved with it, from
   `cron_auth_legacy` to any non-2xx on `/internal/cron/*`.
7. **Monitoring** is committed too — `infra/gcp/80-uptime-checks.sh` creates
   uptime checks on `/health` *and* on a database-backed route, because `/health`
   never touches Postgres and reported `ok` throughout an outage. Alerts require
   two failing locations sustained for five minutes.
8. **Staging deploys itself on merge to `main`** (touching `backend/**` or either
   service file). Production stays `workflow_dispatch` with the typed `deploy`,
   and a push cannot reach it.

### Rolling back

Full procedure — including the two things it cannot undo — is
**[design/infra-rollback.md](design/infra-rollback.md)**. The tourniquet, when
production is serving something bad and you do not want to wait for a build:

```bash
gcloud run services update-traffic myweli-api --region europe-west9 --to-revisions <previous-revision>=100
```

Three things about that command are worth knowing *before* you need it:

- **It undoes itself.** Both service files commit `traffic: latestRevision:
  true`, and the next `replace` writes that back — so the pin silently stops
  holding at the next deploy. It buys minutes; the fix is a `git revert`. The
  deploy workflow now refuses to lift a pin unless the run says `unpin: yes`.
- **Only `status.traffic[].revisionName` tells you what is serving.** After a
  pin, both `spec.template…image` and `status.latestReadyRevisionName` name the
  revision you rolled *away from*, and they agree with each other.
- **It does not touch the database.** Migrations are forward-only. Rollback is
  safe today because all 31 are additive, and a test now keeps it that way.
- **It does not roll back secrets, and it may move them forward.** The old
  revision starts a new container, and every mount is `key: latest` — resolved at
  container start. So it comes up holding whatever the *current* secret values
  are, not the ones it originally ran with. If the thing you are rolling away
  from included a secret change, the rollback does not undo it; and older code
  meets a newer value it may not understand.

## Phase D — Deploy the web (Vercel)
Project root = `web/`. Env: `API_BASE_URL=https://api.myweli.com` (server-side BFF)
· `NEXT_PUBLIC_API_BASE_URL=https://api.myweli.com` · `NEXT_PUBLIC_SITE_URL=https://myweli.com`
· `NEXT_PUBLIC_MYWELI_WHATSAPP=225…` · `NEXT_PUBLIC_IOS_APP_URL` /
`NEXT_PUBLIC_ANDROID_APP_URL` (after the apps ship). Point `myweli.com` DNS →
Vercel; confirm `WEB_ORIGINS` matches. Verify `/sitemap.xml`, `/robots.txt`,
`/llms.txt`, JSON-LD, `/opengraph-image`, `/logo.svg` (a real raster `logo.png` +
designed OG art can replace the generated ones later).

## Phase E — Deploy the admin (Cloudflare Pages, via GitHub Actions)
The admin is a Flutter-Web SPA that calls `api.myweli.com` **directly** (CORS), so
`WEB_ORIGINS` must include `https://admin.myweli.com` (set in
`infra/gcp/service.yaml`; it is a boot fail-fast, so a deploy that drops it never
serves rather than failing silently in the browser).
- **Build + deploy:** `.github/workflows/deploy-admin.yml` builds
  `lib/main_admin.dart` (`--dart-define=API_BASE_URL=https://api.myweli.com`) and
  deploys to the **Cloudflare Pages** project `myweli-admin`. Repo secrets:
  `CLOUDFLARE_API_TOKEN` (Pages:Edit) + `CLOUDFLARE_ACCOUNT_ID`.
- **Domain:** in the Pages project → Custom domains → add `admin.myweli.com`
  (Cloudflare auto-creates the DNS record since the zone is on Cloudflare).
- **Restrict:** put **Cloudflare Access** (Zero Trust) in front of the Pages site —
  email-allowlist to your address(es). The backend also enforces admin authz +
  the seeded `ADMIN_EMAIL`/`ADMIN_PASSWORD` login, but Access keeps the console
  unreachable to the public.
- **Rotating the admin password is NOT done by changing the secret.**
  `ADMIN_PASSWORD` is **bootstrap only**: `ensureSeedAdmin` is insert-only, so on
  any database that already holds the admin the mounted value is read and
  **discarded**. Changing the secret and redeploying looks like a rotation and
  changes nothing; the boot log prints a `NOTICE` saying so. Rotate with
  `POST /admin/auth/password` (current + new password, ≥12 chars), which also
  revokes every admin refresh token
  ([backend-admin-password-change.md](design/backend-admin-password-change.md)).
  Update the secret afterwards too, so a database bootstrapped from scratch
  later does not come up holding the old password.

### Web rebuild hook (configured 2026-08-21)

The web's `/[slug]` route sets `dynamicParams = false` — the only mechanism that
makes Next serve a real 404 in the served HTML rather than a 44-character blank
shell. Its slug set is therefore fixed at **build** time, so a salon that becomes
publicly listable after the last build would 404 until the next one.

The backend asks Vercel to rebuild on the three transitions that change the
listable set (salon created / suspended / restored). Configuration, all done:

1. Vercel → `myweli` → Settings → Git → **Deploy Hooks**, on the production
   branch.
2. `WEB_DEPLOY_HOOK_URL` in Secret Manager, with
   `roles/secretmanager.secretAccessor` for `myweli-run@`. **Treat it as a
   credential** — anyone holding it can trigger unlimited (paid) builds.
3. Mounted in `infra/gcp/service.yaml`. **Production only**: staging is where
   salons are created and suspended while testing, and a staging event would
   trigger a *production* build. `service_files_test.dart` pins that asymmetry
   and pins that the value comes from Secret Manager rather than a literal.

**Confirmed live, 2026-08-21 — and precisely how far.** POSTing the hook URL
returned `HTTP 201` with a `PENDING` job and Vercel started a production
deployment, so the URL is real and the status matches what the backend logs
(`status=201`). It is mounted on revision `myweli-api-00028-zhs`, and the boot
log carries **no** `WEB_DEPLOY_HOOK_URL` warning — which is what distinguishes
the HTTP notifier from the silent no-op.

**One hop is still unexercised, and saying so is the point.** Nothing has proven
that *Cloud Run reaches Vercel* on a real salon change: production holds zero
salons, so there is nothing to create, suspend or restore. The first real salon
exercises it — success logs `site_rebuild sent reason=salon.created status=201`,
and a blocked egress would log `site_rebuild FAILED` while the salon is still
created, because the notifier fails open.

**Confirming that last hop:** suspend a salon in the admin console and a deployment
starts in Vercel within seconds; the backend logs
`site_rebuild sent reason=provider.suspend status=201` — reason and status only,
never the URL. An unparseable URL prints a `WARNING` at boot, so a quiet boot log
means it resolved.

Two deliberate behaviours: a **60s per-process cooldown** (rapid changes trigger
one build; a dropped event is safe because the next build reads the current set)
and it **fails open** — an unreachable hook is logged, never propagated, because
the write that triggered it already succeeded. Design:
[backend-web-rebuild-hook.md](design/backend-web-rebuild-hook.md).

## Phase F — Mobile apps
1. **Android — scaffolded ✅ (#3).** Two Gradle flavors: `consumer`
   (`com.myweli.app`, "Myweli") + `pro` (`com.myweli.pro`, "Myweli Pro"). Realign
   the **iOS** bundle ids to match (`com.myweli.app` / `com.myweli.pro`).

   ⚠️ **Measured 2026-07-28 by building both entrypoints, and it is more than a
   rename.** iOS has **no flavour mechanism at all**: one scheme (`Runner`), and
   `PRODUCT_BUNDLE_IDENTIFIER` is **`com.sadreddine.myweli.pro` in all three
   configurations**. So `flutter build ios --target lib/main.dart` — the
   **consumer** app — reports *"Building com.sadreddine.myweli.pro"*, the two
   apps cannot be installed side by side on one device, and the consumer app
   would ship under a `.pro` identifier. Android solves this with
   `productFlavors`; iOS needs the equivalent (a scheme + xcconfig per flavour),
   not a find-and-replace. The test target also still carries Flutter's default
   `com.example.myweli.RunnerTests`. Two App Store listings need two distinct
   ids, so this blocks the iOS half of launch.
2. **Push — real FCM ✅ (2026-07-14).** The `firebase_messaging` adapter,
   foreground display, tap→deep-link (with the pro salon switch), the OS-denied
   re-enable path and the pro notification centre all ship. What remains is
   console work: **§B4** (the two `google-services.json`, the service account,
   the cron, the device smoke test) — and, for iOS, the Apple developer account.
3. Real launcher icons/splash (per flavor); iOS signing (Apple Dev); Android
   signing keystore (`key.properties`, gitignored).
4. Build prod (per flavor):
   `flutter build appbundle --flavor consumer -t lib/main.dart
   --dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com`
   (and `--flavor pro -t lib/main_pro.dart`).
5. Store listings + privacy policy; submit to App Store + Play.
6. Set `NEXT_PUBLIC_IOS_APP_URL` / `NEXT_PUBLIC_ANDROID_APP_URL` on the web.

## Phase G — Go-live checklist

> **What CI now proves for free, and what still needs the paid pass (Q1).**
> The first four links of the chain below — discovery → provider page → booking
> → pro accepts — are asserted on **every PR** by the funnel e2e, against the
> AOT binary on real Postgres (`backend/tool/smoke/funnel_smoke_test.dart`). So
> arriving here, those are regressions rather than unknowns.
> **Still manual and still paid, every one of them because it needs an account:**
> real OTP **SMS**, **WhatsApp** confirmation, the **reminder cron**, **R2**
> photo upload, and **push**. Q1 deliberately touches none of them — no SMS is
> ever sent, at $0.49/segment.

End-to-end on prod: discovery → provider page → booking + **real OTP SMS** → pro
accepts → **WhatsApp confirmation** → **reminder cron** → **R2 photo upload** →
**push**. Plus: Postgres backups, monitoring/logs/uptime alerts (Sentry), DNS/SSL,
verify the API's rate-limits + security headers, and **make the GitHub repo private
again** with a small Actions spending limit (or accept the monthly quota).

---

## Remaining code work (no accounts needed — makes deploy turnkey)
- ✅ `backend/Dockerfile` + `.dockerignore`.
- ✅ App push seam + permission UX (#2) — token → `/me/devices`.
- ✅ **Real FCM (2026-07-14)** — `firebase_messaging` adapter, foreground
  display, tap→deep-link + pro salon switch, OS-denied re-enable path, the pro
  notification centre, Android/iOS scaffolding. Only the Firebase console steps
  remain (§B4); iOS is code-complete but needs the Apple account to build.
- ✅ Android project scaffolded (#3) — flavors `consumer` (`com.myweli.app`) +
  `pro` (`com.myweli.pro`); real launcher icons + `google-services.json` later.
- ✅ Pro-app push wiring (#2b) — provider-session registration + first-dashboard-visit prompt.
- ✅ Web `next/image` + CDN allowlist (`cdn.myweli.com`) + OG image
  (`app/opengraph-image.tsx`) + favicon + `logo.svg` (#4). Real raster `logo.png`
  / designed OG art = optional later polish.
- ✅ Infrastructure-as-code for the backend — originally the Render Blueprint
  (`render.yaml`), now `infra/gcp/service.yaml` + `deploy-backend.yml`. The
  Blueprint did its job and is deleted; what carried over is the property that
  made it worth having — **the infrastructure is in the repo and reviewable.**

**→ The no-account deployment-readiness track (#1–#4 + #2b) is complete.**
Everything remaining is the accounts phase (provision services + supply keys).
