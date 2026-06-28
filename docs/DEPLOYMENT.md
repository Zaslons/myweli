# Myweli — deployment & accounts runbook

The end-to-end guide to take Myweli live. Domain: **`myweli.com`**. Nothing here
needs secrets in git — every key is set in the host's secret manager. Source of
truth for backend keys: [`backend/.env.example`](../backend/.env.example); for web:
[`web/.env.example`](../web/.env.example).

## 0. What runs where
| Component | Tech | Host | Domain |
|---|---|---|---|
| Backend API | dart_frog + Postgres | **Fly.io** (Docker, region `cdg`) | `api.myweli.com` |
| Web | Next.js | **Vercel** | `myweli.com` + `www` |
| Admin console | Flutter Web | static host (Vercel/CF Pages) | `admin.myweli.com` |
| Mobile | Flutter (consumer + pro) | App Store + Google Play | — |
| Object storage | Cloudflare R2 (3 buckets) | Cloudflare | `cdn.myweli.com` (public bucket) |
| Messaging | Twilio (WhatsApp + SMS) | Twilio | webhook → `api.myweli.com` |
| Push | Firebase Cloud Messaging | Firebase | — |
| DNS/CDN | Cloudflare | Cloudflare | `myweli.com` zone |
| Errors | Sentry (optional) | Sentry | — |

**Recommended stack** (scalability + cost; all portable — Docker + S3-compatible +
standard Postgres): Fly.io · Neon (serverless Postgres) · Vercel · Cloudflare R2 ·
Twilio · Firebase FCM · Sentry. Alternatives: Cloud Run/Render (backend), Supabase
(DB), Cloudflare Pages (web), Africa's Talking (cheaper CI SMS — swappable behind
the messaging interface). Region: **EU (Paris)** — best latency to West Africa.

No payment gateway: deposits are **no-custody** (salons use their own Wave/MoMo);
Myweli never holds funds.

---

## Phase A — Accounts to open
Domain ✅ (`myweli.com`). Then: Fly.io · Neon · Vercel · Cloudflare (R2+DNS) ·
Twilio · Firebase · Apple Developer ($99/yr) · Google Play ($25 once) · Sentry
(free) · a Myweli business WhatsApp number.

## Phase B — Provision services
**B1. Postgres (Neon):** create a project (EU); copy `DATABASE_URL`. Keep a warm
paid tier (no cold starts for bookings).

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

## Phase C — Deploy the backend
1. **Image:** `backend/Dockerfile` (multi-stage → minimal runtime; migrations on
   boot). `fly launch` (or Cloud Run deploy) from `backend/`.
2. **Env** (host secret manager — NEVER a committed file): `ENV=prod` ·
   `JWT_SECRET` (48-byte random; generator in `.env.example`) · `DATABASE_URL` ·
   all `R2_*` · all `TWILIO_*` · `MESSAGING_WEBHOOK_SECRET` · `CRON_SECRET` · all
   `FCM_*` · `WEB_ORIGINS=https://myweli.com,https://www.myweli.com` ·
   `ADMIN_EMAIL` + `ADMIN_PASSWORD` (seeds the first admin).
3. Deploy → migrations run → verify `GET https://api.myweli.com/health`.
4. **Twilio webhook:** status callback →
   `https://api.myweli.com/webhooks/messaging/status?secret=<MESSAGING_WEBHOOK_SECRET>`.
5. **Reminder cron:** an external scheduler `POST /internal/cron/reminders` with
   `X-Cron-Secret: <CRON_SECRET>` every ~15 min (24h/2h reminders).

## Phase D — Deploy the web (Vercel)
Project root = `web/`. Env: `API_BASE_URL=https://api.myweli.com` (server-side BFF)
· `NEXT_PUBLIC_API_BASE_URL=https://api.myweli.com` · `NEXT_PUBLIC_SITE_URL=https://myweli.com`
· `NEXT_PUBLIC_MYWELI_WHATSAPP=225…` · `NEXT_PUBLIC_IOS_APP_URL` /
`NEXT_PUBLIC_ANDROID_APP_URL` (after the apps ship). Point `myweli.com` DNS →
Vercel; confirm `WEB_ORIGINS` matches. Verify `/sitemap.xml`, `/robots.txt`,
`/llms.txt`, JSON-LD; add real `/logo.png` + OG image.

## Phase E — Deploy the admin
`flutter build web --target lib/main_admin.dart` → static host at
`admin.myweli.com`; restrict access (internal ops; admin login + seeded
`ADMIN_EMAIL`).

## Phase F — Mobile apps
1. **Scaffold Android** (only `ios/`,`macos/`,`web/` exist): `flutter create
   --platforms=android .` in `mobile/`; app id `com.myweli` (or `ci.myweli`).
2. Add `google-services.json` (Android) + `GoogleService-Info.plist` (iOS); enable
   iOS Push capability; wire **`firebase_messaging`** (token → `POST /me/devices`).
3. App icons/splash; iOS bundle id + Apple signing; Android keystore.
4. Build prod: `--dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com`
   (consumer `main.dart` + pro `main_pro.dart`).
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
- ✅ `backend/Dockerfile` + `.dockerignore` (this PR).
- ☐ App `firebase_messaging` wiring (token → `/me/devices`).
- ☐ `flutter create --platforms=android` scaffold + app id/icons.
- ☐ `next.config` image domain for `cdn.myweli.com` (switch `<img>`→`next/image`)
  + real OG image + `logo.png`.
- ☐ Host-specific config (`fly.toml` / Cloud Run YAML) — once the host is chosen.
