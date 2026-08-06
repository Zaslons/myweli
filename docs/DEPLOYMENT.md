# Myweli — deployment & accounts runbook

The end-to-end guide to take Myweli live. Domain: **`myweli.com`**. Nothing here
needs secrets in git — every key is set in the host's secret manager. Source of
truth for backend keys: [`backend/.env.example`](../backend/.env.example); for web:
[`web/.env.example`](../web/.env.example).

## 0. What runs where
| Component | Tech | Host | Domain |
|---|---|---|---|
| Backend API | dart_frog (Docker) | **Render** (Frankfurt, EU) — `render.yaml` Blueprint | `api.myweli.com` |
| Database | PostgreSQL | **Render Postgres** (same region) | internal |
| Web | Next.js | **Vercel** | `myweli.com` + `www` |
| Admin console | Flutter Web | static host (Vercel/CF Pages) | `admin.myweli.com` |
| Mobile | Flutter (consumer + pro) | App Store + Google Play | — |
| Object storage | Cloudflare R2 (3 buckets) | Cloudflare | `cdn.myweli.com` (public bucket) |
| Messaging | Twilio (WhatsApp + SMS) | Twilio | webhook → `api.myweli.com` |
| Push | Firebase Cloud Messaging | Firebase | — |
| DNS/CDN | Cloudflare | Cloudflare | `myweli.com` zone |
| Errors | Sentry (optional) | Sentry | — |

**Stack — built to scale without re-platforming.** Render (backend + Postgres,
Frankfurt) · Vercel (web) · Cloudflare R2 (images) · Twilio (WhatsApp/SMS) ·
Firebase FCM (push) · Sentry. What protects you from a forced migration is
**standard interfaces** — Docker, the Postgres wire protocol, the S3 API, Next.js
— not the vendor; each piece is individually swappable.

> **Why Render, not Cloud Run.** Cloud Run + Cloud SQL is the higher-ceiling
> choice and stays the upgrade target, but **GCP billing rejects prepaid/virtual
> cards** (common in CI). Render is **Stripe-billed** (accepts the same cards
> Twilio does), **deploys from GitHub in the console** (auto-deploy on push), has
> **built-in managed Postgres**, and runs the **same `backend/Dockerfile`** — so
> moving to Cloud Run later (if a GCP-friendly card appears) is config, not a
> rewrite. Alternatives via the same interfaces: Railway / DigitalOcean (PayPal!)
> / Fly.io (backend), Neon / Supabase (DB), Cloudflare Pages (web), Africa's
> Talking (cheaper CI SMS). Region: **EU (Frankfurt)** — good latency to West Africa.

No payment gateway: deposits are **no-custody** (salons use their own Wave/MoMo);
Myweli never holds funds.

---

## Phase A — Accounts to open
Domain ✅ (`myweli.com`). Then: **Render** (backend + Postgres) · Vercel ·
Cloudflare (R2+DNS) · Twilio ✅ · Firebase · Apple Developer ($99/yr) · Google Play
($25 once) · Sentry (free) · a Myweli business WhatsApp number.

## Phase B — Provision services
**B1. Postgres (Render):** provisioned by the `render.yaml` Blueprint alongside the
web service (Frankfurt). `DATABASE_URL` is injected automatically (`fromDatabase`);
the backend connects over SSL (`SslMode.require`). The Blueprint starts on the free
DB tier — **upgrade to a paid plan (backups + no 90-day expiry) before launch.**

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
5. **Reminder cron** — Render Cron Job, `POST /internal/cron/reminders` with the
   `X-Cron-Secret` header, every ~15 min (Phase C step 5).
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

## Phase C — Deploy the backend (Render, from `render.yaml`)
1. **Render Dashboard → New → Blueprint** → connect the GitHub repo → it reads
   `render.yaml` and provisions **myweli-db** (Postgres) + **myweli-api** (web,
   builds `backend/Dockerfile`, context `backend/`). `autoDeploy` redeploys on push.
2. **Secrets** (web service → Environment tab; `sync: false` keys, never in git):
   `ADMIN_EMAIL` + `ADMIN_PASSWORD` (seeds the first admin) · all `TWILIO_*`
   (`TWILIO_SMS_FROM=Myweli`) · all `R2_*` · all `FCM_*`. `DATABASE_URL`,
   `JWT_SECRET`, `MESSAGING_WEBHOOK_SECRET`, `CRON_SECRET`, `ENV`, `WEB_ORIGINS`
   are set by the Blueprint (generated/wired). Migrations run on boot.
3. Verify `GET <render-url>/health`, then map the custom domain `api.myweli.com`
   (Render → Settings → Custom Domains → add the CNAME at Cloudflare).
4. **Twilio webhook:** status callback →
   `https://api.myweli.com/webhooks/messaging/status?secret=<MESSAGING_WEBHOOK_SECRET>`.
5. **Reminder cron:** a **Render Cron Job** (or any scheduler) that
   `POST`s `/internal/cron/reminders` with `X-Cron-Secret: <CRON_SECRET>` every
   ~15 min (24h/2h reminders).

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
`WEB_ORIGINS` must include `https://admin.myweli.com` (done in `render.yaml`).
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
- ✅ Render Blueprint (`render.yaml`) — backend web service + Postgres, from GitHub.

**→ The no-account deployment-readiness track (#1–#4 + #2b) is complete.**
Everything remaining is the accounts phase (provision services + supply keys).
