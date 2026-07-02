# Authentication overhaul — Google Sign-In + Apple + Email OTP (phone → contact)

| | |
|---|---|
| **Requirement** | FR-AUTH-001/002 (account + sign-in). Re-platforms login off SMS-OTP. |
| **Phase** | Accounts / launch — unblock a $0, no-business sign-in for Côte d'Ivoire |
| **Status** | **Building** — 6 decisions locked (2026-06-30); **Phase 1 (backend) built 2026-07-02** (§17); web → mobile → pro next. |
| **Decision** | **Google Sign-In** (primary) + **Apple Sign-In** (iOS **+ web**) + **Email OTP** (fallback). Phone-OTP login **deactivated** at launch (code dormant). Phone becomes **contact info**, verified later via Termii. |
| **Supersedes (for launch)** | Phone-OTP as the *primary* login — kept **dormant** (code + Termii rails stay) for post-registration phone verification |
| **Cross-refs** | [messaging-termii.md](messaging-termii.md) · memory `sms-channel-cost-decision` · [openapi.yaml](../api/openapi.yaml) · BACKEND.md §3 (auth) |

---

## 1. Goal & scope

### Why
SMS-OTP to CI is the wrong launch foundation: every no-business sender is expensive (**Twilio $0.49**, **Firebase Phone Auth $0.29** per OTP), and the only cheap route (**Termii ~$0.023**) is **gated on company registration**, which is 3–6 months out. We need an auth that is **free, needs no registered business, and works today** — and for an ~85–90% Android market that is **Google Sign-In**, with **email OTP** for the rest and **Apple Sign-In** to satisfy Apple's App-Store rule on iOS.

Phone-number identity isn't abandoned — it's **demoted to a contact attribute** (so salons can reach clients) and will be **verified later, cheaply, via Termii** once the company is registered.

### In scope
- Backend: Google + Apple ID-token verification, email-OTP, new identity model + migration, `EmailProvider` seam.
- Mobile **consumer** app (Flutter): Google + Apple + email-OTP login; phone collected as contact.
- **Web** consumer (Next.js): Google + **Apple** + email-OTP via the existing BFF/httpOnly-cookie session.
- Pro (app + web): same model, **phased after consumer** (§11).
- Booking-funnel change: confirmation now requires **sign-in**, not a phone OTP (§9.4 / §10.3).

### Out of scope (deferred, tracked)
- **Phone verification** (post-registration, via Termii) — `phone_verified` stays `false` for now.
- **WhatsApp** auth/notifications (needs Meta business verification).
- Removing the dormant phone-OTP code paths.

---

## 2. Decision & rationale

| Option | Cost/OTP to CI | Business needed | Verdict |
|---|---|---|---|
| **Google Sign-In** | **$0** | ❌ | **Primary** — free, Android-fit |
| **Email OTP** | ~free (email) | ❌ | **Fallback** for non-Google users |
| **Apple Sign-In** | $0 | ❌ (indiv. Apple dev acct) | **iOS app only** — App-Store rule 4.8 |
| Firebase Phone Auth | $0.29 | ❌ | Rejected — still expensive |
| Twilio SMS-OTP | $0.49 | ❌ | Rejected — too expensive |
| Termii SMS-OTP | $0.023 | ✅ | **Later** — phone verification post-registration |

**Principle that keeps this contained:** the identity provider (Google/Apple/email) only **proves who the user is**; **we keep our own session** (the existing HS256 access JWT + rotating refresh family in `TokenService`/`AuthRepository`). So nothing downstream of login changes — middleware, principal resolution, ownership checks, all routes stay as-is.

---

## 3. Architecture overview

```
                         ┌───────────────────────────────────────────────┐
 Mobile app / Web        │                  Myweli backend                │
 ───────────────         │  (dart_frog — unchanged session model)         │
                         │                                                │
 [Continuer avec Google] │  POST /auth/google {idToken}                   │
   → google_sign_in /    │     → GoogleIdTokenVerifier (JWKS, aud, iss,    │
     GIS returns a       │        exp, email_verified)                    │
     Google **ID token** │     → SocialAuthService.findOrCreate(claims)   │
   ───── idToken ──────▶ │     → AuthRepository issues TokenPair (family) │
                         │     ◀── AuthSession { tokens, user } ──────────│
                         │                                                │
 [Continuer avec Apple]  │  POST /auth/apple {identityToken, nonce}       │  (iOS)
   (sign_in_with_apple)  │     → AppleIdTokenVerifier (Apple JWKS …)      │
                         │                                                │
 [Continuer avec e-mail] │  POST /auth/email/otp/request {email}          │
   enter email → code    │     → EmailOtpService (gen+hash+TTL+throttle)  │
                         │     → EmailProvider.send(code)                 │
                         │  POST /auth/email/otp/verify {email, code}     │
                         │     → AuthSession { tokens, user }             │
                         │                                                │
 (web only)              │  BFF /api/auth/* → backend → httpOnly cookies  │
                         └───────────────────────────────────────────────┘
```

The token a client sends us (`idToken`/`identityToken`) is a **JWT signed by Google/Apple**. We **never trust its contents until verified** against the provider's public keys; only then do we mint *our* tokens.

---

## 4. Identity & account model

- **Canonical identity = verified email.** Google and Apple both return a `sub` (stable provider user id) and (usually) a verified email.
- A user row carries: `email` (unique), `google_sub` (unique, nullable), `apple_sub` (unique, nullable), and a now-**nullable** `phone` + `phone_verified`.
- **Linking rules (find-or-create):**
  1. Look up by the provider `sub` (e.g. `google_sub`). Match → that user.
  2. Else look up by **verified** `email`. Match → **link** this provider's `sub` to that user (so Google + email-OTP on the same address are one account).
  3. Else create a new user (email + sub, `phone = null`, `phone_verified = false`).
- **Account-takeover guard:** only link on a **verified** email (`email_verified == true` from Google; Apple emails are verified). Never link on an unverified/self-asserted email.
- **Apple private relay:** Apple may return a relay address (`…@privaterelay.appleid.com`) and only sends the real name/email on **first** authorization. Persist whatever Apple gives on first sign-in; key by `apple_sub` thereafter (the relay email is stable per user+app).

---

## 5. The contract (OpenAPI — locked in the same PR)

All success responses reuse the existing **`AuthSession`** shape (do **not** drift — this bit us before): `{ "tokens": { "accessToken", "refreshToken", "expiresAt" }, "user": User }`.

| Method · Path | Body | Success | Errors |
|---|---|---|---|
| `POST /auth/google` | `{ idToken }` | `200 AuthSession` | 400 `invalid_token` · 401 `token_rejected` · 403 `account_suspended` |
| `POST /auth/apple` | `{ identityToken, nonce?, fullName?, email? }` | `200 AuthSession` | as above |
| `POST /auth/email/otp/request` | `{ email }` | `200 { sent: true, expiresInSeconds, devCode? }` | 400 `invalid_email` · 429 `otp_resend_limit` |
| `POST /auth/email/otp/verify` | `{ email, code }` | `200 AuthSession` | 400 `otp_invalid`/`otp_expired`/`otp_none`/`otp_locked` · 403 `account_suspended` |
| `POST /auth/refresh` | `{ refreshToken }` | `200 { tokens }` | **unchanged** |
| `PATCH /me` | `{ name?, email?, phone? }` | `200 User` | sets the **contact** phone (`phone_verified` stays false) |

`devCode` returned **only** when `ENV != prod` (mirrors SMS-OTP). `User` schema gains `email` (already present), keeps `phoneNumber` but it becomes nullable; add `authProvider` (`google`/`apple`/`email`).

---

## 6. Data model & migration

New migration `00NN_auth_social_email.sql`:

```sql
ALTER TABLE users
  ADD COLUMN email           TEXT,
  ADD COLUMN email_verified  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN google_sub      TEXT,
  ADD COLUMN apple_sub       TEXT,
  ADD COLUMN auth_provider   TEXT,           -- 'google' | 'apple' | 'email' | 'phone'
  ADD COLUMN display_name    TEXT,
  ADD COLUMN avatar_url      TEXT;

ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;     -- phone now optional
ALTER TABLE users ADD COLUMN phone_verified BOOLEAN NOT NULL DEFAULT FALSE;

CREATE UNIQUE INDEX users_email_key      ON users (lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX users_google_sub_key ON users (google_sub)   WHERE google_sub IS NOT NULL;
CREATE UNIQUE INDEX users_apple_sub_key  ON users (apple_sub)    WHERE apple_sub IS NOT NULL;
```

**Pre-launch:** only seed/test users exist → safe to wipe the `users` table; no production migration of real accounts. The phone-OTP columns/logic remain (dormant) for later phone verification.

---

## 7. Backend design (layering — docs/BACKEND.md §1)

### Routes (thin: parse → verify → delegate → shape; 405 on bad verbs)
- `routes/auth/google.dart` · `routes/auth/apple.dart`
- `routes/auth/email/otp/request.dart` · `routes/auth/email/otp/verify.dart`
- (later, pro) `routes/auth/provider/google.dart`, etc.

### Services (no dart_frog, no SQL — the testable core)
- **`GoogleIdTokenVerifier`** — fetches & **caches Google's JWKS** (`https://www.googleapis.com/oauth2/v3/certs`, honour `Cache-Control`), verifies **RS256 signature**, `iss ∈ {accounts.google.com, https://accounts.google.com}`, `aud ∈` our **allowlist** of OAuth client IDs (web + android + ios), `exp`/`iat` within skew, `email_verified == true`. Returns `(sub, email, name, picture)` or a typed failure.
- **`AppleIdTokenVerifier`** — Apple JWKS (`https://appleid.apple.com/auth/keys`), `iss = https://appleid.apple.com`, `aud = ` our app/service id, `exp`, and **`nonce`** match (replay defence). Apple emails count as verified.
- **`SocialAuthService`** — takes verified claims → `AuthRepository.findOrCreateBySocial(...)` (link rules §4) → returns `AuthSession` via the existing family-issuing path. Rejects `status == 'banned'` → `account_suspended`.
- **`EmailOtpService`** — **reuses** the existing OTP mechanics (6-digit, `TokenService.hashToken`, 5-min TTL, attempt/resend budget, `LoginThrottle`) but keys by **email** and delivers via `EmailProvider`. Dev code inline only off-prod. Never logs the code.

### The `EmailProvider` seam (mirror of `MessagingProvider`)
```dart
abstract interface class EmailProvider {
  Future<EmailSendResult> send({required String to, required String subject, required String body});
}
class LogEmailProvider implements EmailProvider { … }   // dev/CI, no network
class ResendEmailProvider implements EmailProvider { … } // prod (or SES/SMTP)
```
Selected in `dependencies.dart` like the messaging provider (configured → real; else log; prod fail-fast). Config: `EMAIL_PROVIDER`, `RESEND_API_KEY` (or SES creds), `EMAIL_FROM` (`no-reply@myweli.com`). All `sync:false`, never in git; documented in `.env.example` + `render.yaml`.

### Repository extensions (`AuthRepository` + Postgres + in-memory)
```dart
Future<AuthUser?> findByGoogleSub(String sub);
Future<AuthUser?> findByAppleSub(String sub);
Future<AuthUser?> findByEmail(String email);
Future<AuthUser> findOrCreateBySocial({           // link rules §4, issues nothing
  required String provider, required String sub,
  required String email, String? name, String? avatarUrl });
Future<OtpRequestResult> requestEmailOtp(String email);
Future<OtpVerifyResult>  verifyEmailOtp(String email, String code);
```
`AuthUser.phoneNumber` becomes **nullable**; add `authProvider`. The existing `requestOtp/verifyOtp` (phone) stay for the dormant path.

### Config / env (new)
`GOOGLE_CLIENT_IDS` (comma-sep audiences), `APPLE_CLIENT_ID`/`APPLE_SERVICE_ID`, `APPLE_TEAM_ID`, `EMAIL_PROVIDER`, `RESEND_API_KEY`, `EMAIL_FROM`. Verifiers configured → real; unset off-prod → a permissive dev stub is **not** allowed (verification must be real even in dev for these — use test tokens in tests).

---

## 8. Security & threat model (docs/BACKEND.md §3, §7)

- **Token verification is the trust boundary.** Verify signature (JWKS), `aud` allowlist, `iss`, `exp/iat` (±60s skew), and `email_verified`/`nonce`. **Never** decode-without-verify; never trust client-sent email/sub.
- **Email OTP:** hashed at rest, 5-min TTL, attempt + resend budget + `LoginThrottle`, **dev code inline only off-prod**, never logged. **Enumeration:** `request` always returns `{ sent: true }` regardless of whether the email maps to a user.
- **Account linking** only on a **verified** email (§4) → no takeover via unverified email collision.
- **Session unchanged:** 15-min access JWT + opaque rotating refresh family, reuse → family revoke, logout clears. So all existing authz (deny-by-default, ownership → 403) is untouched.
- **Secrets** via env (`sync:false`), never in git; gitleaks must stay green.
- **New STRIDE entries:** **T31** forged/replayed Google ID token (→ JWKS+aud+exp), **T32** email-OTP brute-force/enumeration (→ throttle+lockout+constant response), **T33** account-link takeover (→ verified-email-only linking), **T34** Apple relay/first-auth data handling.

**Required negative tests** (auth-touching): forged signature → 401, wrong `aud` → 401, expired → 401, `email_verified:false` → reject, email-OTP lockout after N attempts, enumeration returns identical response, cross-tenant token still → 403.

---

## 9. Mobile — consumer app (Flutter, `main.dart`)

### Packages & platform config
- `google_sign_in` (Google), `sign_in_with_apple` (Apple, iOS).
- **Android:** OAuth client ID + **SHA-1/SHA-256** in the Google project; `google-services` not required if we verify server-side (we do).
- **iOS:** reversed-client-ID URL scheme; **Sign in with Apple** capability/entitlement; Apple Developer account.

### Flow & screens (UX-first — design to DESIGN-STANDARDS tokens)
- **Login screen** (`phone_login_screen` → re-themed `login_screen`): brand header, then buttons in order:
  1. **Continuer avec Google** (Google-branded button per their guidelines)
  2. **Continuer avec Apple** (iOS only, Apple HIG button)
  3. **Continuer avec e-mail** → email screen
- **Email screen:** step 1 enter email → step 2 enter 6-digit code (reuse the existing OTP code-entry widget); `devCode` shown off-prod.
- **`returnTo` continuity** preserved (deep-link back to the gated action after login).
- **Four states** each (loading spinner on the button, error banner, success → navigate). **French** copy.
- **Phone**: collected later as **contact** — at first booking and in profile — labelled *« Votre numéro pour que le salon vous contacte »*, **not** verified.

### App architecture (existing patterns)
- `AuthServiceInterface` gains `signInWithGoogle()`, `signInWithApple()`, `requestEmailOtp(email)`, `verifyEmailOtp(email, code)` — **mock** (simulated latency/errors) + **Api** impls. Keep `requestOtp/verifyOtp` (phone) for the dormant path behind a flag.
- `AuthProvider` (ChangeNotifier) exposes `isLoading/error`; tokens persisted in **`flutter_secure_storage`** (unchanged); `go_router` redirect/`returnTo` unchanged.
- Errors: user-cancelled (silent), network, `token_rejected`, `account_suspended` → mapped French messages.

### Booking-flow change
The booking confirm step currently sends a **phone OTP**. It becomes: **must be signed in** (Google/Apple/email) to confirm; the phone is collected as contact, not verified. If signed out at confirm → present the login sheet with `returnTo` back to confirm.

---

## 10. Web — consumer (Next.js, `web/`)

### Google
- **Google Identity Services (GIS)**: render the official "Sign in with Google" button → on credential, POST the **ID token** to the **BFF** `POST /api/auth/google` → BFF calls backend `/auth/google` → sets the existing **httpOnly** session cookies (`setSessionCookies`). **No tokens in JS** (keeps the WEB.md security rule).
- One GOOGLE client ID for web origin(s); CORS/origins already locked.

### Email OTP
- `/connexion` gains an "e-mail" path: form → BFF `/api/auth/email/otp/request` then `/verify` → cookies. Mirrors the existing OTP form component.

### Apple on web (in scope — decision)
- **Sign in with Apple JS**: render the Apple button → on success POST the `identityToken` (+ `nonce`) to BFF `POST /api/auth/apple` → backend `/auth/apple` → httpOnly cookies. Requires an Apple **Service ID** (separate from the iOS app id) + a **verified domain** (return URL on `myweli.com`). `AppleIdTokenVerifier` accepts both the iOS app `aud` and the web Service-ID `aud` from its allowlist.

### Booking funnel
- `BookingFlow` confirm step swaps phone-OTP for **sign-in** (Google/email) via the same BFF; phone field stays only as **contact** input. e2e updated accordingly (the funnel no longer types an OTP — it authenticates).

### Conventions
- Public auth pages `noindex`; SSR; design tokens; **four states**; **French**; app-install push retained; typed OpenAPI client regenerated.

---

## 11. Pro (app + web) — phased after consumer

Salons are low-volume, so SMS cost is negligible for them; but unify for consistency. **Phase 3**: pro app + pro web get **Google + email** the same way (registration/KYC onboarding then proceeds unchanged). Pro phone-OTP stays available (dormant) until then. No change to KYC, dashboard, or provider authz.

---

## 12. Design / UX (DESIGN-STANDARDS + WEB-DESIGN-STANDARDS)

- **Button order & styling:** Google (primary, brand-compliant) → Apple (iOS, HIG-compliant black/white) → e-mail (tertiary/text). Reuse `AppButton`/web `Button`; **tokens only**, no literals.
- **Copy (FR):** *« Continuer avec Google »*, *« Continuer avec Apple »*, *« Continuer avec e-mail »*; email screen *« Entrez votre e-mail »* / *« Entrez le code reçu par e-mail »*; errors *« Connexion annulée »*, *« E-mail invalide »*, *« Code incorrect ou expiré »*, *« Compte suspendu »*.
- **Phone-as-contact** prompt copy (booking/profile) as in §9.
- **Web** keeps desktop-creative latitude (memory `web-design-latitude`); mobile app mirrors the app flow.
- A short mockup is added to this spec before build (login screen, email step, booking-confirm sign-in).

---

## 13. Email infrastructure

- **Provider:** **Resend** (simple API, free tier ~3k/mo) recommended; SES as the scale option (seam makes it swappable).
- **Domain auth:** SPF + **DKIM** + DMARC on `myweli.com`; `EMAIL_FROM = no-reply@myweli.com` for deliverability.
- **OTP email (FR):** subject *« Votre code Myweli »*, body *« Votre code de vérification Myweli est 123456. Il expire dans 5 minutes. »* (plain + minimal HTML).

---

## 14. Errors, performance, testing, rollout

**Errors:** standard envelope `{ error, message? }`; codes per §5; no stack/JWKS/credential leakage.

**Performance:** JWKS cached (no fetch per request); token verify is CPU-cheap; no N+1; mobile cold-start unaffected; web auth pages meet CWV.

**Testing (DoD):**
- *Backend unit:* verifiers (mocked JWKS — valid, bad-sig, wrong-aud, expired, bad-nonce), `SocialAuthService` find/create/**link**, `EmailOtpService` throttle/lockout/expiry.
- *Handler:* success + 4xx + 405 for each route; **contract** matches OpenAPI.
- *Security/negative:* §8 list.
- *Mobile:* `AuthProvider` unit, login-screen widget, sign-in flow on mocks.
- *Web:* RTL unit, Playwright e2e (Google credential **stubbed**, email-OTP happy path, signed-out booking → login → confirm), auth-negative.

**Rollout / phasing (zero-risk, flag-gated `AUTH_METHODS`):**
1. **Backend** — endpoints + verifiers + `EmailProvider` + migration; phone-OTP kept. Ship behind flag.
2. **Web consumer** — Google + email; booking funnel switch.
3. **Mobile consumer** — Google + Apple + email; booking switch.
4. **Pro** (app + web).
5. **Later:** phone verification via **Termii** post-registration (flip `MESSAGING_PROVIDER=termii`, add a verify-phone step) — rails already merged (#157).

---

## 15. Decisions (locked 2026-06-30)
1. **Email provider → Resend.**
2. **Apple Sign-In → now, on iOS *and* web** (§10.3).
3. **Pro auth → switch** to Google/Apple/email in Phase 3 (unify).
4. **Phone-OTP login → deactivated at launch** (no UI entry); code + Termii rails kept dormant for post-registration phone verification.
5. **Wipe the test `users` table** pre-launch (no real accounts).
6. **Google project / client IDs** (web + Android + iOS) — user creates a free Google Cloud project; IDs gathered during build.

## 16. Brand assets & placeholders

Build proceeds now with **labelled placeholders**; real files are a drop-in later.

### Login mockup (mobile; web adapts to a centered card on desktop)
```
        ┌──────────────────────────┐
        │         [ LOGO ]         │   ← SVG, swappable placeholder
        │          Myweli          │
        │    Beauté & bien-être    │
        │                          │
        │  ┌────────────────────┐  │
        │  │ G  Continuer avec  │  │   Google (brand button)
        │  └────────────────────┘  │
        │  ┌────────────────────┐  │
        │  │    Continuer avec  │  │   Apple (HIG black; iOS + web)
        │  └────────────────────┘  │
        │  ┌────────────────────┐  │
        │  │  Continuer avec    │  │   e-mail (tertiary)
        │  └────────────────────┘  │
        │  En continuant, vous     │
        │  acceptez les CGU…       │
        └──────────────────────────┘
  (Open animation: Lottie plays over the splash before this screen)
```

### Assets to provide later (formats)
| Asset | Format | Spec | For |
|---|---|---|---|
| **Logo** | **SVG** + 1024 px PNG master | Horizontal lockup **and** square mark; **dark-on-light + light-on-dark** (brand is monochrome) | all surfaces |
| **App icon** | **1024×1024 PNG** master (square, **no** transparency, **no** rounded corners, sRGB) | + Android adaptive **foreground PNG 1024×1024 with ~25 % safe padding** + background hex. **Separate consumer vs pro** icons. I generate every size via `flutter_launcher_icons`. | consumer app · pro app |
| **Favicon / web icons** | **SVG mark** + 512 px PNG | I derive `favicon.ico` (16/32/48), `apple-touch-icon` (180), PWA icons (192/512) | web · admin web |
| **Open splash (static)** | **PNG** (transparent mark, centered, ≥1152 px) + background hex | the OS splash can show only a static logo on a colour (`flutter_native_splash`) | consumer app · pro app |
| **Open animation** | **Lottie `.json`** (~1–2 s, < 200 KB) + optional MP4/GIF fallback | plays in-app right after the static splash; Flutter `lottie` + web `lottie-react` | all (web optional) |

Defaults until you specify: splash background **white `#FAFAFA`**; logo + favicon shared across surfaces; consumer/pro differ only on icon + splash.

## 17. Build notes — Phase 1 (backend, built 2026-07-02)

Deltas from the plan (all in the spirit of "match the existing pattern"):
- **`SocialAuthService` folded into `AuthRepository.loginWithSocial`** — find-or-create/link is storage logic, exactly like `verifyOtp`'s find-or-create; routes stay thin (parse → verify via the injected verifier → delegate → `authSessionResponse`). The verifiers (`GoogleIdTokenVerifier`/`AppleIdTokenVerifier` over a `JwksCache`) are the standalone testable core.
- **`authSessionResponse` helper in `responses.dart`** — one place shapes the nested `{tokens:{...},user}` AuthSession (the drift that broke the web BFF once can't recur per-route).
- **`users.phone_number` UNIQUE dropped** (migration `0022`) — phone is contact data, not identity; two accounts may share a contact number. The dormant phone-OTP path is `LIMIT 1` + disabled via `AUTH_METHODS`. Existing users get `phone_verified = true` (they proved it via SMS-OTP).
- **`AUTH_METHODS` fail-fast is opt-in**: prod boot only *requires* per-method config (`GOOGLE_CLIENT_IDS` etc.) when `AUTH_METHODS` is set explicitly — an unset legacy deploy keeps booting, with the new endpoints failing closed (503 `auth_not_configured`). Zero-risk merge; activation = set the env vars in Render.
- **Apple `fullName`** accepted as a display-name-only hint (never for linking); nonce accepted raw or SHA-256 (iOS convention).
- Threat model **T31–T34** added (BACKEND.md §7); auto-sync (T26) now keys on **`phone_verified`**.
- Tests: **+31** (verifier w/ real RSA keys + mocked JWKS incl. rotation; link rules incl. the T33 negative; email-OTP budgets/lockout/expiry; route handlers + AUTH_METHODS gate) → **285 backend tests**.
