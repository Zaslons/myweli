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

**B4. Firebase/FCM** (spec: push-notifications-fcm): create project; add iOS +
Android apps (download `GoogleService-Info.plist` + `google-services.json`); create
a service account. Keys → `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`
(keep `\n` escapes).

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
2. Add `google-services.json` (Android) + `GoogleService-Info.plist` (iOS); enable
   iOS Push capability; ship the real **`FcmPushNotificationService`** (the app
   token-registration seam + permission UX already ship — #2; this is the last
   plugin impl, then flip the DI line).
3. Real launcher icons/splash (per flavor); iOS signing (Apple Dev); Android
   signing keystore (`key.properties`, gitignored).
4. Build prod (per flavor):
   `flutter build appbundle --flavor consumer -t lib/main.dart
   --dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com`
   (and `--flavor pro -t lib/main_pro.dart`).
5. Store listings + privacy policy; submit to App Store + Play.
6. Set `NEXT_PUBLIC_IOS_APP_URL` / `NEXT_PUBLIC_ANDROID_APP_URL` on the web.

## Phase G — Go-live checklist
End-to-end on prod: discovery → provider page → booking + **real OTP SMS** → pro
accepts → **WhatsApp confirmation** → **reminder cron** → **R2 photo upload** →
**push**. Plus: Postgres backups, monitoring/logs/uptime alerts (Sentry), DNS/SSL,
verify the API's rate-limits + security headers, and **make the GitHub repo private
again** with a small Actions spending limit (or accept the monthly quota).

---

## Remaining code work (no accounts needed — makes deploy turnkey)
- ✅ `backend/Dockerfile` + `.dockerignore`.
- ✅ App push seam + permission UX on mocks (#2) — token → `/me/devices`; real
  `firebase_messaging` impl deferred to the accounts phase.
- ✅ Android project scaffolded (#3) — flavors `consumer` (`com.myweli.app`) +
  `pro` (`com.myweli.pro`); real launcher icons + `google-services.json` later.
- ✅ Pro-app push wiring (#2b) — provider-session registration + first-dashboard-visit prompt.
- ✅ Web `next/image` + CDN allowlist (`cdn.myweli.com`) + OG image
  (`app/opengraph-image.tsx`) + favicon + `logo.svg` (#4). Real raster `logo.png`
  / designed OG art = optional later polish.
- ✅ Render Blueprint (`render.yaml`) — backend web service + Postgres, from GitHub.

**→ The no-account deployment-readiness track (#1–#4 + #2b) is complete.**
Everything remaining is the accounts phase (provision services + supply keys).
